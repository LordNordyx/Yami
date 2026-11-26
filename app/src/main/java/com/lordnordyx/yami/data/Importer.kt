package com.lordnordyx.yami.data

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.charset.Charset
import java.util.zip.ZipFile
import kotlin.coroutines.coroutineContext

/** Brings games into the library from a folder, a .zip, or in place. */
class Importer(private val context: Context, private val repo: GameRepository) {

    data class Progress(val stage: String, val done: Long, val total: Long, val current: String = "")

    sealed interface Result {
        data class Ok(val game: Game) : Result
        data class Failed(val reason: String) : Result
    }

    /** Copy a folder picked through the system file picker into app storage. */
    suspend fun importTree(tree: Uri, onProgress: (Progress) -> Unit): Result = withContext(Dispatchers.IO) {
        val root = DocumentFile.fromTreeUri(context, tree) ?: return@withContext Result.Failed("Folder not readable")
        val staging = File(repo.gamesRoot, ".import-${System.nanoTime()}").apply { mkdirs() }
        try {
            onProgress(Progress("Scanning", 0, 0))
            val files = ArrayList<Pair<DocumentFile, String>>()
            collect(root, "", files)
            val total = files.sumOf { it.first.length() }
            var done = 0L
            for ((doc, rel) in files) {
                coroutineContext.ensureActive()
                val out = File(staging, rel).apply { parentFile?.mkdirs() }
                context.contentResolver.openInputStream(doc.uri)?.use { input ->
                    out.outputStream().use { input.copyTo(it, 1 shl 16) }
                }
                done += doc.length()
                onProgress(Progress("Copying", done, total, rel))
            }
            finish(staging, inPlace = false)
        } catch (t: Throwable) {
            staging.deleteRecursively()
            Result.Failed(t.message ?: t.javaClass.simpleName)
        }
    }

    private fun collect(dir: DocumentFile, prefix: String, out: MutableList<Pair<DocumentFile, String>>) {
        for (f in dir.listFiles()) {
            val name = f.name ?: continue
            val rel = if (prefix.isEmpty()) name else "$prefix/$name"
            if (f.isDirectory) collect(f, rel, out) else out += f to rel
        }
    }

    /** Extract a .zip (UTF-8 names, falling back to the Windows OEM code page). */
    suspend fun importZip(zip: Uri, onProgress: (Progress) -> Unit): Result = withContext(Dispatchers.IO) {
        val tmpZip = File(context.cacheDir, "import.zip")
        val staging = File(repo.gamesRoot, ".import-${System.nanoTime()}").apply { mkdirs() }
        try {
            onProgress(Progress("Reading archive", 0, 0))
            context.contentResolver.openInputStream(zip)?.use { i -> tmpZip.outputStream().use { i.copyTo(it, 1 shl 16) } }
                ?: return@withContext Result.Failed("Archive not readable")
            val zf = runCatching { ZipFile(tmpZip, Charsets.UTF_8).also { z -> z.entries().toList() } }
                .getOrElse { ZipFile(tmpZip, Charset.forName("IBM437")) }
            zf.use { z ->
                val entries = z.entries().toList()
                val total = entries.sumOf { it.size.coerceAtLeast(0) }
                var done = 0L
                val base = staging.canonicalPath
                for (e in entries) {
                    coroutineContext.ensureActive()
                    val out = File(staging, e.name.replace('\\', '/'))
                    if (!out.canonicalPath.startsWith(base)) continue // zip-slip guard
                    if (e.isDirectory) { out.mkdirs(); continue }
                    out.parentFile?.mkdirs()
                    z.getInputStream(e).use { i -> out.outputStream().use { i.copyTo(it, 1 shl 16) } }
                    done += e.size.coerceAtLeast(0)
                    onProgress(Progress("Extracting", done, total, e.name))
                }
            }
            finish(staging, inPlace = false)
        } catch (t: Throwable) {
            staging.deleteRecursively()
            Result.Failed(t.message ?: t.javaClass.simpleName)
        } finally {
            tmpZip.delete()
        }
    }

    /** Register a folder where it already lives (needs all-files access). */
    suspend fun importInPlace(tree: Uri): Result = withContext(Dispatchers.IO) {
        val path = treeUriToPath(tree) ?: return@withContext Result.Failed("Can't resolve this folder to a file path")
        val dir = File(path)
        if (!dir.canRead()) return@withContext Result.Failed("No access. Grant \"All files access\" in Settings.")
        val game = GameScanner.locate(dir) ?: return@withContext Result.Failed("No RPG Maker game found in this folder")
        Result.Ok(register(game, inPlace = true))
    }

    /** Scan a folder of many games (in place) and add every game found. */
    suspend fun scanLibraryFolder(tree: Uri): List<Game> = withContext(Dispatchers.IO) {
        val path = treeUriToPath(tree) ?: return@withContext emptyList()
        File(path).listFiles()?.filter { it.isDirectory }
            ?.mapNotNull { GameScanner.locate(it, 1) }
            ?.filter { dir -> repo.games.value.none { it.path == dir.absolutePath } }
            ?.map { register(it, inPlace = true) } ?: emptyList()
    }

    private fun finish(staging: File, inPlace: Boolean): Result {
        val gameDir = GameScanner.locate(staging)
            ?: run { staging.deleteRecursively(); return Result.Failed("No RPG Maker game found") }
        val det = GameScanner.detect(gameDir)
        var finalDir = File(repo.gamesRoot, sanitize(det.title))
        var n = 2
        while (finalDir.exists()) finalDir = File(repo.gamesRoot, "${sanitize(det.title)} ($n)").also { n++ }
        if (!gameDir.renameTo(finalDir)) {
            gameDir.copyRecursively(finalDir, overwrite = true)
        }
        staging.deleteRecursively()
        return Result.Ok(register(finalDir, inPlace))
    }

    fun register(dir: File, inPlace: Boolean): Game {
        val det = GameScanner.detect(dir)
        val id = GameScanner.idFor(dir)
        val existing = repo.game(id)
        val game = (existing ?: Game(id = id, title = det.title, path = dir.absolutePath)).copy(
            title = existing?.title ?: det.title,
            rgssVersion = det.rgssVersion,
            engineHint = det.engineHint,
            coverPath = det.cover?.absolutePath,
            iconPath = det.icon?.absolutePath,
            inPlace = inPlace,
        )
        repo.upsert(game)
        if (repo.settings.value.hideFromGallery) File(dir, ".nomedia").createNewFile()
        return game
    }

    private fun sanitize(s: String) = s.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "Game" }.take(64)

    companion object {
        fun treeUriToPath(tree: Uri): String? {
            val docId = runCatching { DocumentsContract.getTreeDocumentId(tree) }.getOrNull() ?: return null
            val type = docId.substringBefore(':')
            val rel = docId.substringAfter(':', "")
            val base = if (type.equals("primary", true)) Environment.getExternalStorageDirectory().absolutePath
                       else "/storage/$type"
            return if (rel.isEmpty()) base else "$base/$rel"
        }
    }
}
