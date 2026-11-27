package com.lordnordyx.yami.engine

import android.content.Context
import com.lordnordyx.yami.data.AppSettings
import com.lordnordyx.yami.data.Game
import com.lordnordyx.yami.data.GameRepository
import com.lordnordyx.yami.data.GameSettings
import com.lordnordyx.yami.data.ScreenFit
import com.lordnordyx.yami.data.WidescreenMode
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.io.File

/**
 * Turns a game + its settings into what the engine needs on disk:
 *  - mkxp.json in the game folder (merged over the developer's own mkxp.json)
 *  - yami.cfg, read by the Ruby runtime layer (widescreen, turbo, map cache…)
 */
object EngineConfig {

    const val MARKER = "_yami"
    const val TURBO_SCANCODE = 67 // SDL_SCANCODE_F10
    const val MENU_SCANCODE = 68  // SDL_SCANCODE_F11 (reserved)

    data class Prepared(val gameDir: File, val dataDir: File, val cfgFile: File)

    fun prepare(
        context: Context,
        repo: GameRepository,
        game: Game,
        displayAspect: Float,
        optimizeMode: Boolean = false,
    ): Prepared {
        val s = repo.effectiveSettings(game)
        val app = repo.settings.value
        val runtime = RuntimeAssets.install(context, repo)
        val gameDir = File(game.path)
        val dataDir = repo.saveDir(game.id)

        val ratio = when {
            optimizeMode || s.widescreen == WidescreenMode.OFF -> 0f
            s.aspect.ratio > 0f -> s.aspect.ratio
            else -> displayAspect
        }

        val cfg = File(runtime.dir, "session-${game.id}.cfg")
        cfg.writeText(buildString {
            appendLine("game_id=${game.id}")
            appendLine("rgss=${if (s.rgssVersionOverride in 1..3) s.rgssVersionOverride else game.rgssVersion}")
            appendLine("mode=${if (optimizeMode) "optimize" else "play"}")
            appendLine("widescreen=${if (optimizeMode) "off" else s.widescreen.name.lowercase()}")
            appendLine("ratio=$ratio")
            appendLine("turbo_mode=${s.turboMode.name.lowercase()}")
            appendLine("turbo_speed=${s.turboSpeed}")
            appendLine("turbo_toggle=${s.turboToggle}")
            appendLine("turbo_scancode=$TURBO_SCANCODE")
            appendLine("map_cache=${s.mapCache}")
            appendLine("map_cache_mb=${s.mapCacheMb}")
            appendLine("optimized_maps=${s.optimizedMaps}")
            appendLine("warm_graphics=${s.warmGraphics}")
            appendLine("redirect_saves=${s.redirectSaves && !game.inPlace}")
            appendLine("save_dir=${dataDir.absolutePath}")
            appendLine("status_file=${File(runtime.dir, "status-${game.id}.txt").absolutePath}")
        })

        val rgss = if (s.rgssVersionOverride in 1..3) s.rgssVersionOverride else game.rgssVersion
        val vsync = s.vsync && displayPacesEvenly(context, if (rgss == 1) 40f else 60f)
        writeMkxpJson(gameDir, buildOverrides(game, s.copy(vsync = vsync), app, runtime, cfg, optimizeMode))
        return Prepared(gameDir, dataDir, cfg)
    }

    /**
     * vsync only helps when the display can refresh at a whole multiple of the
     * game's rate (RPG Maker XP: 40 fps -> 80/120 Hz; the player asks Android
     * for that mode). On a 60 Hz-only screen a 40 fps game with vsync waits for
     * an extra refresh on most frames and drops towards 30 fps; without vsync
     * the engine keeps its own steady 40.
     */
    private fun displayPacesEvenly(context: Context, rate: Float): Boolean = runCatching {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as android.hardware.display.DisplayManager
        val display = dm.getDisplay(android.view.Display.DEFAULT_DISPLAY) ?: return@runCatching true
        display.supportedModes.any { m ->
            val k = Math.round(m.refreshRate / rate)
            k >= 1 && kotlin.math.abs(m.refreshRate - k * rate) < 1.5f
        }
    }.getOrDefault(true)

    private fun buildOverrides(
        game: Game, s: GameSettings, app: AppSettings,
        rt: RuntimeAssets.Installed, cfg: File, optimizeMode: Boolean,
    ): Map<String, JsonElement> {
        val m = LinkedHashMap<String, JsonElement>()
        fun p(k: String, v: Any) {
            m[k] = when (v) {
                is Boolean -> JsonPrimitive(v); is Number -> JsonPrimitive(v); else -> JsonPrimitive(v.toString())
            }
        }
        p(MARKER, true)
        if (s.rgssVersionOverride in 1..3) p("rgssVersion", s.rgssVersionOverride)
        p("fullscreen", true)
        p("winResizable", true)
        p("fixedAspectRatio", s.fit != ScreenFit.STRETCH)
        p("integerScalingActive", s.fit == ScreenFit.INTEGER)
        p("integerScalingLastMile", false)
        p("smoothScaling", s.scaling.code)
        p("smoothScalingDown", minOf(s.scaling.code, 3))
        p("bicubicSharpness", s.bicubicSharpness)
        p("xbrzScalingFactor", s.xbrzFactor)
        p("framebufferScalingFactor", s.internalResolution.toDouble())
        p("enableHires", s.hiresTextures)
        if (s.hiresTextures) p("textureScalingFactor", s.hiresTextureScale.toDouble())
        p("vsync", s.vsync)
        p("syncToRefreshrate", false)
        p("fixedFramerate", s.fixedFramerate)
        p("frameSkip", s.frameSkip)
        p("displayFPS", s.showEngineFps)
        p("pathCache", true)
        // Yami tells map code from UI by script section name ("NNN:Name").
        p("useScriptNames", true)
        p("enableSettings", false) // F1 desktop menu is useless on touch; Yami has its own
        p("enableReset", true)
        if (s.fontScale > 0f) p("fontScale", s.fontScale.toDouble())
        p("midiSoundFont", s.soundFont)
        p("midiReverb", s.midiReverb)
        p("midiChorus", s.midiChorus)
        p("SESourceCount", 8)
        p("dataPathOrg", "Yami")
        p("dataPathApp", game.id)
        p("windowTitle", game.title)

        val shaderFile = rt.shader(s.shader)
        p("postShader", shaderFile?.absolutePath ?: "")
        p("postShaderIntensity", s.shaderIntensity.toDouble())

        m["RTP"] = JsonArray(app.rtpPaths.filter { File(it).isDirectory }.map { JsonPrimitive(it) })

        // Ruby 1.8 compatibility (scripts written for RMXP's Ruby) and Win32API
        // emulation (older Essentials calls Windows DLLs at load).
        val pre = mutableListOf(rt.script("yami_runtime.rb"), rt.script("yami_ruby18.rb"), rt.script("yami_win32.rb"))
        if (optimizeMode) pre += rt.script("yami_optimizer.rb")
        m["preloadScript"] = JsonArray(pre.map { JsonPrimitive(it.absolutePath) })
        return m
    }

    private val lenientJson = Json { isLenient = true; ignoreUnknownKeys = true }

    /**
     * Keeps the developer's mkxp.json intact: the first time we touch a game we
     * stash the original and always merge on top of it. Array keys that the
     * developer set (preloadScript, RTP) are concatenated, not replaced.
     */
    private fun writeMkxpJson(gameDir: File, overrides: Map<String, JsonElement>) {
        val target = File(gameDir, "mkxp.json")
        val orig = File(gameDir, "mkxp.json.original")
        if (target.exists() && !orig.exists()) {
            val txt = target.readText()
            if (!txt.contains("\"$MARKER\"")) target.copyTo(orig)
        }
        val base: Map<String, JsonElement> = if (orig.exists()) {
            runCatching { lenientJson.parseToJsonElement(stripJson5(orig.readText())).jsonObject.toMap() }
                .getOrDefault(emptyMap())
        } else emptyMap()

        val merged = LinkedHashMap(base)
        for ((k, v) in overrides) {
            val b = base[k]
            merged[k] = if (v is JsonArray && b is JsonArray) JsonArray(v + b)
                        else if (v is JsonArray && b is JsonPrimitive) JsonArray(v + b) else v
        }
        // The developer's own preloads must still run after ours.
        target.writeText(Json { prettyPrint = true }.encodeToString(JsonObject.serializer(), JsonObject(merged)))
    }

    /** mkxp.json is JSON5: strip comments and trailing commas. */
    fun stripJson5(src: String): String {
        val out = StringBuilder(src.length)
        var i = 0
        var inStr = false
        var quote = '"'
        while (i < src.length) {
            val c = src[i]
            if (inStr) {
                out.append(c)
                if (c == '\\' && i + 1 < src.length) { out.append(src[i + 1]); i += 2; continue }
                if (c == quote) inStr = false
                i++; continue
            }
            when {
                c == '"' || c == '\'' -> { inStr = true; quote = c; out.append('"'); i++
                    // normalise single-quoted strings to double quotes
                    if (c == '\'') {
                        while (i < src.length && src[i] != '\'') {
                            if (src[i] == '"') out.append("\\\"") else out.append(src[i]); i++
                        }
                        out.append('"'); inStr = false; i++
                    }
                }
                c == '/' && i + 1 < src.length && src[i + 1] == '/' -> { while (i < src.length && src[i] != '\n') i++ }
                c == '/' && i + 1 < src.length && src[i + 1] == '*' -> {
                    i += 2; while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) i++; i += 2
                }
                else -> { out.append(c); i++ }
            }
        }
        return out.toString().replace(Regex(",(\\s*[}\\]])"), "$1")
    }
}
