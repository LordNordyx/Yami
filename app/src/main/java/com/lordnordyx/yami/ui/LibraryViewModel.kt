package com.lordnordyx.yami.ui

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lordnordyx.yami.YamiApp
import com.lordnordyx.yami.data.AppSettings
import com.lordnordyx.yami.data.Game
import com.lordnordyx.yami.data.GameSettings
import com.lordnordyx.yami.data.Importer
import com.lordnordyx.yami.data.LibrarySort
import com.lordnordyx.yami.data.OptimizeReport
import com.lordnordyx.yami.data.SaveManager
import com.lordnordyx.yami.engine.RuntimeAssets
import com.lordnordyx.yami.optimize.GameOptimizer
import com.lordnordyx.yami.player.PlayerActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class LibraryViewModel(app: Application) : AndroidViewModel(app) {

    val repo = (app as YamiApp).repo
    private val importer = Importer(app, repo)
    private val optimizer = GameOptimizer(repo)
    val saves = SaveManager(app, repo)

    val settings: StateFlow<AppSettings> = repo.settings
    val query = MutableStateFlow("")

    val games: StateFlow<List<Game>> = combine(repo.games, repo.settings, query) { list, s, q ->
        val filtered = if (q.isBlank()) list else list.filter {
            it.title.contains(q, true) || it.engineHint.contains(q, true) || it.tags.any { t -> t.contains(q, true) }
        }
        val sorted = when (s.sort) {
            LibrarySort.RECENT -> filtered.sortedWith(compareByDescending<Game> { it.lastPlayed }.thenByDescending { it.addedAt })
            LibrarySort.TITLE -> filtered.sortedBy { it.title.lowercase() }
            LibrarySort.ADDED -> filtered.sortedByDescending { it.addedAt }
            LibrarySort.PLAYTIME -> filtered.sortedByDescending { it.playTimeSec }
        }
        sorted.sortedByDescending { it.favorite }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    /** Busy state shown as a progress sheet. */
    data class Busy(val title: String, val detail: String = "", val fraction: Float = -1f)
    val busy = MutableStateFlow<Busy?>(null)
    val message = MutableStateFlow<String?>(null)
    /** Report of a crashed game session, shown once when returning to the library. */
    val crashReport = MutableStateFlow<String?>(null)
    private var job: Job? = null

    // Engine round-trips (optimizer run, then the game itself)
    private data class Pending(val gameId: String, val base: OptimizeReport, val thenPlay: Boolean)
    private var pending: Pending? = null

    fun cancel() { job?.cancel(); busy.value = null }

    // ----------------------------------------------------------------- import
    private fun runImport(block: suspend ((Importer.Progress) -> Unit) -> Importer.Result) {
        job = viewModelScope.launch {
            busy.value = Busy("Importing")
            val r = block { p ->
                busy.value = Busy(p.stage, p.current.substringAfterLast('/'),
                    if (p.total > 0) p.done.toFloat() / p.total else -1f)
            }
            busy.value = null
            when (r) {
                is Importer.Result.Ok -> {
                    message.value = "Added ${r.game.title}"
                    if (repo.settings.value.optimizeOnImport) optimize(r.game.id, thenPlay = false)
                }
                is Importer.Result.Failed -> message.value = r.reason
            }
        }
    }

    fun importFolder(uri: Uri) = runImport { cb -> importer.importTree(uri, cb) }
    fun importZip(uri: Uri) = runImport { cb -> importer.importZip(uri, cb) }
    fun addInPlace(uri: Uri) = runImport { _ -> importer.importInPlace(uri) }

    fun scanFolder(uri: Uri) {
        viewModelScope.launch {
            busy.value = Busy("Scanning for games")
            val found = importer.scanLibraryFolder(uri)
            busy.value = null
            message.value = if (found.isEmpty()) "No new games found" else "Added ${found.size} game(s)"
        }
    }

    // ------------------------------------------------------------- optimize
    fun optimize(id: String, thenPlay: Boolean, ctx: Context? = null) {
        val g = repo.game(id) ?: return
        job = viewModelScope.launch {
            busy.value = Busy("Optimizing", g.title, 0f)
            val report = runCatching {
                optimizer.prepare(g) { s -> busy.value = Busy(s.label, s.detail.substringAfterLast('/'), s.fraction) }
            }.getOrElse {
                busy.value = null
                message.value = "Optimization failed: ${it.message}"
                return@launch
            }
            val s = repo.effectiveSettings(g)
            if (g.rgssVersion == 1 && s.optimizedMaps && report.maps > 0) {
                // Phase 2 runs inside the engine; we pick the result up in onReturnFromEngine().
                pending = Pending(id, report, thenPlay)
                busy.value = Busy("Building compact tilesets", "The engine is analysing maps…", 0.75f)
                PlayerActivity.launch(ctx ?: getApplication<Application>(), id, optimize = true)
            } else {
                repo.update(id) { it.copy(optimize = report.copy(note = "Archive & index ready")) }
                busy.value = null
                if (thenPlay) launchGame(ctx ?: getApplication<Application>(), id)
            }
        }
    }

    fun onReturnFromEngine() {
        repo.absorbStats()
        viewModelScope.launch(Dispatchers.IO) {
            com.lordnordyx.yami.player.CrashReports.collect(getApplication<Application>())?.let { crashReport.value = it }
        }
        val p = pending ?: return
        val g = repo.game(p.gameId) ?: run { pending = null; return }
        // The optimizer engine process may still be writing; give it a moment.
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                val f = File(g.path, ".yami/opt/result.txt")
                var tries = 0
                while (!f.exists() && tries++ < 20) kotlinx.coroutines.delay(150)
                optimizer.readEngineResult(g, p.base)
            }
            repo.update(g.id) { it.copy(optimize = result) }
            pending = null
            busy.value = null
            message.value = result.note.ifBlank { "Optimized" }
            if (p.thenPlay) launchGame(getApplication<Application>(), g.id)
        }
    }

    fun deleteOptimized(id: String) = repo.game(id)?.let { optimizer.deleteOptimized(it); message.value = "Optimized data removed" }
    fun restoreArchive(id: String) = repo.game(id)?.let {
        message.value = if (optimizer.restoreArchive(it)) "Original archive restored" else "No archive backup found"
    }

    // ----------------------------------------------------------------- play
    fun play(ctx: Context, id: String, skipOptimize: Boolean = false) {
        val g = repo.game(id) ?: return
        if (!skipOptimize && g.optimize == null && repo.settings.value.optimizeOnImport) {
            optimize(id, thenPlay = true, ctx = ctx)
        } else launchGame(ctx, id)
    }

    private fun launchGame(ctx: Context, id: String) {
        repo.update(id) { it.copy(lastPlayed = System.currentTimeMillis(), launches = it.launches + 1) }
        PlayerActivity.launch(ctx, id)
    }

    // ------------------------------------------------------------- settings
    fun toggleFavorite(id: String) = repo.update(id) { it.copy(favorite = !it.favorite) }
    fun rename(id: String, title: String) = repo.update(id) { it.copy(title = title.ifBlank { it.title }) }
    fun setGameSettings(id: String, f: (GameSettings) -> GameSettings) =
        repo.update(id) { it.copy(settings = f(it.settings), useGlobalSettings = false) }
    fun useGlobal(id: String, on: Boolean) = repo.update(id) {
        it.copy(useGlobalSettings = on, settings = if (!on && it.useGlobalSettings) repo.settings.value.defaults else it.settings)
    }
    fun updateApp(f: (AppSettings) -> AppSettings) = repo.updateSettings(f)
    fun remove(id: String, deleteFiles: Boolean) = viewModelScope.launch { repo.remove(id, deleteFiles) }

    /** Last crash report if there is one, otherwise the latest session's engine output + system log. */
    fun showLastCrashReport() {
        viewModelScope.launch(Dispatchers.IO) {
            val ctx = getApplication<Application>()
            val crash = com.lordnordyx.yami.player.CrashReports.lastReport(ctx)
            val session = com.lordnordyx.yami.player.CrashReports.sessionLog(ctx)
            crashReport.value = if (crash.exists()) session + "\n\n== Previous crash report ==\n" + crash.readText() else session
        }
    }

    fun shaders() = RuntimeAssets.shaders(getApplication<Application>(), repo)

    fun importShader(uri: Uri) = viewModelScope.launch(Dispatchers.IO) {
        val ctx = getApplication<Application>()
        val name = uri.lastPathSegment?.substringAfterLast('/')?.substringAfterLast(':') ?: "custom.frag"
        val safe = name.replace(Regex("[^\\w.\\-]"), "_").let { if ('.' in it) it else "$it.frag" }
        ctx.contentResolver.openInputStream(uri)?.use { i -> File(repo.userShaderDir, safe).outputStream().use { i.copyTo(it) } }
        message.value = "Shader added: $safe"
    }

    /** Copies a picked .sf2 SoundFont into app storage and returns its path. */
    suspend fun importSoundFont(uri: Uri): String? = withContext(Dispatchers.IO) {
        val ctx = getApplication<Application>()
        val out = File(ctx.filesDir, "soundfonts").apply { mkdirs() }
        val f = File(out, (uri.lastPathSegment?.substringAfterLast('/') ?: "soundfont.sf2").replace(Regex("[^\\w.\\-]"), "_"))
        ctx.contentResolver.openInputStream(uri)?.use { i -> f.outputStream().use { i.copyTo(it) } } ?: return@withContext null
        f.absolutePath
    }

    fun addRtp(uri: Uri) {
        val path = Importer.treeUriToPath(uri) ?: return
        repo.updateSettings { it.copy(rtpPaths = (it.rtpPaths + path).distinct()) }
    }
}
