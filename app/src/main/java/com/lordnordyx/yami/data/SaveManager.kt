package com.lordnordyx.yami.data

import android.content.Context
import android.net.Uri
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Saves live in a per-game folder (saves/<id>) that the engine sees as
 * System.data_directory; classic RMXP games that write Save1.rxdata into the
 * game folder are redirected there by the runtime script. Before each launch
 * a snapshot is taken so a corrupted or overwritten save can be rolled back.
 */
class SaveManager(private val context: Context, private val repo: GameRepository) {

    data class SaveFile(val file: File, val location: String)

    private val saveRegex = Regex("""(?i)^(save\d*|game|file\d*|.*\.sav|.*save.*)\.(rxdata|rvdata2?|sav|dat)$""")

    fun list(game: Game): List<SaveFile> {
        val out = ArrayList<SaveFile>()
        repo.saveDir(game.id).walkTopDown().filter { it.isFile && !it.path.contains("/.snapshots/") }
            .forEach { out += SaveFile(it, "Yami") }
        File(game.path).listFiles()?.filter { it.isFile && saveRegex.matches(it.name) }
            ?.forEach { out += SaveFile(it, "Game folder") }
        return out.sortedByDescending { it.file.lastModified() }
    }

    private fun snapshotsDir(game: Game) = File(repo.saveDir(game.id), ".snapshots")

    fun snapshot(game: Game, keep: Int = 8) {
        val saves = list(game)
        if (saves.isEmpty()) return
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val zip = File(snapshotsDir(game).apply { mkdirs() }, "$stamp.zip")
        writeZip(zip, saves)
        snapshotsDir(game).listFiles()?.sortedByDescending { it.name }?.drop(keep)?.forEach { it.delete() }
    }

    fun snapshots(game: Game): List<File> =
        snapshotsDir(game).listFiles()?.filter { it.extension == "zip" }?.sortedByDescending { it.name } ?: emptyList()

    fun restore(game: Game, zip: File) {
        ZipInputStream(zip.inputStream()).use { zin -> extractInto(game, zin) }
    }

    fun export(game: Game, dest: Uri) {
        context.contentResolver.openOutputStream(dest)?.use { os ->
            ZipOutputStream(os).use { z -> addAll(z, list(game)) }
        }
    }

    fun import(game: Game, src: Uri) {
        context.contentResolver.openInputStream(src)?.use { ZipInputStream(it).use { z -> extractInto(game, z) } }
    }

    private fun writeZip(zip: File, saves: List<SaveFile>) =
        ZipOutputStream(zip.outputStream()).use { z -> addAll(z, saves) }

    private fun addAll(z: ZipOutputStream, saves: List<SaveFile>) {
        for (s in saves) {
            val prefix = if (s.location == "Yami") "data/" else "game/"
            z.putNextEntry(ZipEntry(prefix + s.file.name))
            s.file.inputStream().use { it.copyTo(z) }
            z.closeEntry()
        }
    }

    private fun extractInto(game: Game, zin: ZipInputStream) {
        while (true) {
            val e = zin.nextEntry ?: break
            val name = e.name.substringAfterLast('/')
            if (name.isEmpty() || name.contains("..")) continue
            val target = if (e.name.startsWith("game/")) File(game.path, name) else File(repo.saveDir(game.id), name)
            target.outputStream().use { zin.copyTo(it) }
        }
    }
}
