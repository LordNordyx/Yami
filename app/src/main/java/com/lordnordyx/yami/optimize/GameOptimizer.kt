package com.lordnordyx.yami.optimize

import com.lordnordyx.yami.data.Game
import com.lordnordyx.yami.data.GameRepository
import com.lordnordyx.yami.data.OptimizeReport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Pre-launch optimization, in two phases:
 *
 *  1. Here, on the Kotlin side (fast, no engine):
 *     - unpack Game.rgssad/rgss2a/rgss3a into loose files (archive kept as .yami-bak)
 *     - build a resource index: every file once, case collisions flagged
 *     - write .yami/maps.txt so the runtime can stream map data into RAM
 *     - hide game art from the gallery (.nomedia)
 *
 *  2. In the engine (yami_optimizer.rb, launched in optimize mode):
 *     - per-map compact tilesets for oversized tilesets (only tiles a map uses)
 *     - remapped map copies in .yami/opt, original files untouched
 */
class GameOptimizer(private val repo: GameRepository) {

    data class Step(val label: String, val fraction: Float, val detail: String = "")

    suspend fun prepare(game: Game, onStep: (Step) -> Unit): OptimizeReport = withContext(Dispatchers.IO) {
        val dir = File(game.path)
        val meta = File(dir, ".yami").apply { mkdirs() }
        var report = OptimizeReport(at = System.currentTimeMillis())

        // 1. archive
        val archive = RgssArchive.find(dir)
        if (archive != null) {
            onStep(Step("Unpacking archive", 0f, archive.name))
            val a = RgssArchive(archive)
            // Remember which files we create so "restore" never deletes loose
            // patch files the developer shipped next to the archive.
            val created = a.entries.map { it.name }.filter { !File(dir, it).exists() }
            File(meta, "extracted.txt").writeText(created.joinToString("\n"))
            a.extractAll(dir, false) { done, total, name ->
                onStep(Step("Unpacking archive", 0.4f * done / total, name))
            }
            archive.renameTo(File(dir, archive.name + ".yami-bak"))
            report = report.copy(archiveExtracted = true)
        }

        // 2. resource index
        onStep(Step("Indexing resources", 0.45f))
        val index = HashMap<String, String>()
        var collisions = 0
        val lines = StringBuilder()
        dir.walkTopDown()
            .onEnter { it.name != ".yami" }
            .filter { it.isFile }
            .forEach { f ->
                val rel = f.relativeTo(dir).path.replace('\\', '/')
                val key = rel.lowercase()
                if (index.put(key, rel) != null) collisions++
                // extension-less alias, as RGSS asks for "Graphics/Pictures/Menu"
                index.putIfAbsent(key.substringBeforeLast('.'), rel)
                lines.append(rel).append('\t').append(f.length()).append('\n')
            }
        File(meta, "index.txt").writeText(lines.toString())
        report = report.copy(indexedFiles = lines.count { it == '\n' }, missingRefs = collisions)

        // 3. map manifest
        onStep(Step("Scanning maps", 0.6f))
        val data = dir.listFiles()?.firstOrNull { it.isDirectory && it.name.equals("Data", true) }
        val maps = data?.listFiles()
            ?.filter { it.isFile && MAP_RE.matches(it.name) }
            ?.sortedBy { it.name.lowercase() } ?: emptyList()
        File(meta, "maps.txt").writeText(maps.joinToString("\n") { "Data/${it.name}\t${it.length()}" })
        report = report.copy(maps = maps.size, mapBytes = maps.sumOf { it.length() })

        // 4. gallery hiding
        if (repo.settings.value.hideFromGallery) File(dir, ".nomedia").createNewFile()

        onStep(Step("Ready for map optimization", 0.7f))
        report
    }

    /** Reads the result the in-engine optimizer wrote, merging into the report. */
    fun readEngineResult(game: Game, base: OptimizeReport): OptimizeReport {
        val f = File(game.path, ".yami/opt/result.txt")
        if (!f.exists()) return base.copy(note = "Map optimization did not run")
        val kv = f.readLines().filter { '=' in it }.associate { it.substringBefore('=') to it.substringAfter('=') }
        return base.copy(
            optimizedTilesets = kv["tilesets"]?.toIntOrNull() ?: 0,
            mapVariants = kv["variants"]?.toIntOrNull() ?: 0,
            savedPixels = kv["saved_pixels"]?.toLongOrNull() ?: 0,
            note = kv["note"] ?: "",
        )
    }

    fun deleteOptimized(game: Game) {
        File(game.path, ".yami/opt").deleteRecursively()
        File(game.path, "Graphics/Tilesets/_yami").deleteRecursively()
        repo.update(game.id) { it.copy(optimize = null) }
    }

    /** Puts the original archive back and removes loose files that came from it. */
    fun restoreArchive(game: Game): Boolean {
        val dir = File(game.path)
        val bak = dir.listFiles()?.firstOrNull { it.name.endsWith(".yami-bak") } ?: return false
        val original = File(dir, bak.name.removeSuffix(".yami-bak"))
        if (!bak.renameTo(original)) return false
        val list = File(dir, ".yami/extracted.txt")
        if (list.exists()) {
            list.readLines().filter { it.isNotBlank() }.forEach { File(dir, it).delete() }
            list.delete()
        }
        deleteOptimized(game)
        return true
    }

    companion object {
        val MAP_RE = Regex("""(?i)^Map\d{3,}\.(rxdata|rvdata2?)$""")
    }
}
