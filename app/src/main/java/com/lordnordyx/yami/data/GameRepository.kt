package com.lordnordyx.yami.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/** Single source of truth for the library. Persisted as JSON in app storage. */
/** @param owner true in the library process; the engine process only reads. */
class GameRepository(private val context: Context, private val owner: Boolean = true) {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; prettyPrint = true }
    private val libFile get() = File(context.filesDir, "library.json")
    private val settingsFile get() = File(context.filesDir, "settings.json")

    private val _games = MutableStateFlow<List<Game>>(emptyList())
    val games: StateFlow<List<Game>> = _games.asStateFlow()

    private val _settings = MutableStateFlow(AppSettings())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    val gamesRoot: File get() = File(context.filesDir, "games").apply { mkdirs() }
    fun saveDir(id: String) = File(context.filesDir, "saves/$id").apply { mkdirs() }
    fun statsFile(id: String) = File(context.filesDir, "stats/$id.json").apply { parentFile?.mkdirs() }
    val runtimeDir: File get() = File(context.filesDir, "runtime").apply { mkdirs() }
    val userShaderDir: File get() = File(context.filesDir, "shaders").apply { mkdirs() }

    init { load() }

    private fun load() {
        runCatching { _games.value = json.decodeFromString(libFile.readText()) }
        val hadSettings = settingsFile.exists()
        runCatching { _settings.value = json.decodeFromString(settingsFile.readText()) }
        if (!hadSettings) _settings.value = _settings.value.copy(schema = AppSettings.SCHEMA)
        else if (owner && _settings.value.schema < AppSettings.SCHEMA) migrate(_settings.value.schema)
    }

    /**
     * Settings files store every value, so changed defaults must be applied here.
     * v2: experimental optimized maps and graphics warm-up off by default (they
     * slowed or broke first launches of games on SD cards).
     */
    private fun migrate(from: Int) {
        if (from < 2) {
            fun GameSettings.v2() = copy(optimizedMaps = false, warmGraphics = false)
            _settings.value = _settings.value.copy(defaults = _settings.value.defaults.v2())
            _games.value = _games.value.map { it.copy(settings = it.settings.v2()) }
        }
        if (from < 3) {
            // v3: fill the screen by default (widescreen), and bilinear scaling — the
            // shader-based filters drew the picture at the wrong size on some GPUs.
            fun GameSettings.v3() = copy(
                widescreen = if (widescreen == WidescreenMode.OFF) WidescreenMode.FULL else widescreen,
                scaling = if (scaling.code >= ScalingFilter.BICUBIC.code) ScalingFilter.BILINEAR else scaling,
            )
            _settings.value = _settings.value.copy(defaults = _settings.value.defaults.v3())
            _games.value = _games.value.map { it.copy(settings = it.settings.v3()) }
        }
        if (from < 4) {
            // v4: "Auto" widescreen (panoramic for Pokémon Essentials, whose menus are
            // drawn for 4:3) replaces the v3 default of FULL.
            fun GameSettings.v4() = copy(widescreen = if (widescreen == WidescreenMode.FULL) WidescreenMode.AUTO else widescreen)
            _settings.value = _settings.value.copy(defaults = _settings.value.defaults.v4())
            _games.value = _games.value.map { it.copy(settings = it.settings.v4()) }
        }
        _settings.value = _settings.value.copy(schema = AppSettings.SCHEMA)
        persist()
    }

    @Synchronized
    private fun persist() {
        if (!owner) return
        atomicWrite(libFile, json.encodeToString(_games.value))
        atomicWrite(settingsFile, json.encodeToString(_settings.value))
    }

    private fun atomicWrite(f: File, text: String) {
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(text)
        tmp.renameTo(f)
    }

    fun game(id: String) = _games.value.firstOrNull { it.id == id }

    fun upsert(game: Game) {
        _games.value = _games.value.filterNot { it.id == game.id } + game
        persist()
    }

    fun update(id: String, f: (Game) -> Game) {
        _games.value = _games.value.map { if (it.id == id) f(it) else it }
        persist()
    }

    fun updateSettings(f: (AppSettings) -> AppSettings) {
        _settings.value = f(_settings.value)
        persist()
    }

    /** Effective settings: per-game overrides, or the global defaults. */
    fun effectiveSettings(game: Game): GameSettings {
        val s = if (game.useGlobalSettings) _settings.value.defaults else game.settings
        return if (s.soundFont.isBlank() && _settings.value.defaultSoundFont.isNotBlank())
            s.copy(soundFont = _settings.value.defaultSoundFont) else s
    }

    suspend fun remove(id: String, deleteFiles: Boolean) = withContext(Dispatchers.IO) {
        val g = game(id) ?: return@withContext
        if (deleteFiles && !g.inPlace) File(g.path).deleteRecursively()
        if (deleteFiles) saveDir(id).deleteRecursively()
        _games.value = _games.value.filterNot { it.id == id }
        persist()
    }

    /** Folds session stats written by the engine process back into the library. */
    fun absorbStats() {
        var changed = false
        _games.value = _games.value.map { g ->
            val f = statsFile(g.id)
            if (!f.exists()) return@map g
            val s = runCatching { json.decodeFromString<SessionStats>(f.readText()) }.getOrNull()
            f.delete()
            if (s == null) g else {
                changed = true
                g.copy(playTimeSec = g.playTimeSec + s.seconds, lastPlayed = maxOf(g.lastPlayed, s.endedAt))
            }
        }
        if (changed) persist()
    }

    fun writeStats(id: String, seconds: Long) {
        val f = statsFile(id)
        val prev = runCatching { json.decodeFromString<SessionStats>(f.readText()) }.getOrNull()
        val s = SessionStats((prev?.seconds ?: 0) + seconds, System.currentTimeMillis())
        atomicWrite(f, json.encodeToString(s))
    }

    @Serializable
    data class SessionStats(val seconds: Long, val endedAt: Long)
}
