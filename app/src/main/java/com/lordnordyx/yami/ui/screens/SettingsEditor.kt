package com.lordnordyx.yami.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.FastForward
import androidx.compose.material.icons.outlined.Gamepad
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.Monitor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.vector.ImageVector
import com.lordnordyx.yami.data.AspectPreset
import com.lordnordyx.yami.data.ControllerProfile
import com.lordnordyx.yami.data.GameSettings
import com.lordnordyx.yami.data.Look
import com.lordnordyx.yami.data.MenuSides
import com.lordnordyx.yami.data.ScalingFilter
import com.lordnordyx.yami.data.ScreenFit
import com.lordnordyx.yami.data.TurboMode
import com.lordnordyx.yami.data.WidescreenMode
import com.lordnordyx.yami.ui.ActionRow
import com.lordnordyx.yami.ui.ChoiceRow
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.NavRow
import com.lordnordyx.yami.ui.Section
import com.lordnordyx.yami.ui.SectionNote
import com.lordnordyx.yami.ui.SliderRow
import com.lordnordyx.yami.ui.SwitchRow
import kotlinx.coroutines.launch
import java.io.File

/** Engine options, one sub-menu each. Used for per-game settings and global defaults. */
enum class SettingsCategory(val label: String, val icon: ImageVector) {
    DISPLAY("Display", Icons.Outlined.Monitor),
    GAMEPLAY("Gameplay", Icons.Outlined.AutoAwesome),
    PERFORMANCE("Performance", Icons.Outlined.Bolt),
    SPEED("Speed-up", Icons.Outlined.FastForward),
    INPUT("Overlay & input", Icons.Outlined.Gamepad),
    AUDIO("Audio", Icons.Outlined.GraphicEq),
    COMPAT("Compatibility", Icons.Outlined.Build);

    /** One line describing the current state, shown on the menu row. */
    fun summary(s: GameSettings): String = when (this) {
        DISPLAY -> listOf(Look.of(s).label, s.widescreen.label).joinToString(" · ")
        GAMEPLAY -> listOfNotNull("Instant text".takeIf { s.instantText }, "Minimap".takeIf { s.minimap },
            "Shiny 1/${s.shinyOdds}".takeIf { s.shinyOdds > 0 })
            .ifEmpty { listOf("As the game made it") }.joinToString(" · ")
        PERFORMANCE -> listOfNotNull(
            "GPU maps".takeIf { s.gpuMaps }, "60 FPS".takeIf { s.force60 },
            "Graphics cache".takeIf { s.graphicsCache }, "VSync".takeIf { s.vsync },
        ).ifEmpty { listOf("Game defaults") }.joinToString(" · ")
        SPEED -> "${s.turboMode.label} · ${s.turboSpeed}x${if (s.turboToggle) " · toggle" else ""}"
        INPUT -> listOfNotNull("Touch controls".takeIf { s.showTouchControls }, "Info overlay".takeIf { s.showInfo },
            s.controllerProfile.label.substringBefore(" (")).joinToString(" · ")
        AUDIO -> if (s.soundFont.isBlank()) "Built-in SoundFont" else File(s.soundFont).nameWithoutExtension
        COMPAT -> if (s.rgssVersionOverride == 0) "Auto-detect" else "Forced RGSS${s.rgssVersionOverride}"
    }
}

/** The category menu. */
@Composable
fun SettingsCategoryList(s: GameSettings, title: String? = null, open: (SettingsCategory) -> Unit) {
    Section(title) {
        SettingsCategory.entries.forEach { c -> NavRow(c.label, c.summary(s), c.icon) { open(c) } }
    }
}

/** One category's options. */
@Composable
fun ColumnScope.SettingsCategoryContent(vm: LibraryViewModel, cat: SettingsCategory, s: GameSettings,
                                        onChange: ((GameSettings) -> GameSettings) -> Unit) {
    val shaders = remember { vm.shaders() }
    val scope = rememberCoroutineScope()
    val pickSf2 = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch { vm.importSoundFont(uri)?.let { p -> onChange { it.copy(soundFont = p) } } }
    }

    when (cat) {
        SettingsCategory.DISPLAY -> {
            val look = Look.of(s)
            Section("Look") {
                ChoiceRow("Look", look, Look.presets + listOfNotNull(Look.CUSTOM.takeIf { look == Look.CUSTOM }), { it.label },
                    look.blurb, describe = { it.blurb }) { v -> if (v != Look.CUSTOM) onChange { v.applyTo(it) } }
                SectionNote("Also in the in-game menu (≡) — change it while you play.")
            }
            Section("Screen") {
                ChoiceRow("Widescreen", s.widescreen, WidescreenMode.entries, { it.label }, s.widescreen.blurb, describe = { it.blurb }) { v -> onChange { it.copy(widescreen = v) } }
                if (s.widescreen == WidescreenMode.AUTO || s.widescreen == WidescreenMode.PANORAMIC) {
                    ChoiceRow("Menu sides", s.menuSides, MenuSides.entries, { it.label }, describe = { it.blurb }) { v -> onChange { it.copy(menuSides = v) } }
                }
            }
            var fine by rememberSaveable { mutableStateOf(look == Look.CUSTOM) }
            Section(null) {
                NavRow("Fine-tune", if (fine) "Hide the detailed options" else "Screen fit, filter, shader, resolution…",
                    value = if (fine) "▴" else "▾") { fine = !fine }
            }
            if (fine) {
                Section("Fine-tune") {
                    if (s.widescreen != WidescreenMode.OFF) {
                        ChoiceRow("Aspect ratio", s.aspect, AspectPreset.entries, { it.label }) { v -> onChange { it.copy(aspect = v) } }
                    }
                    ChoiceRow("Screen fit", s.fit, ScreenFit.entries, { it.label.substringBefore(" (") }, describe = {
                        when (it) {
                            ScreenFit.FIT -> "Largest picture that keeps the shape"
                            ScreenFit.INTEGER -> "Whole-number scaling: perfectly even pixels, may leave borders"
                            ScreenFit.STRETCH -> "Fills the screen, distorts the picture"
                        }
                    }) { v -> onChange { it.copy(fit = v) } }
                    ChoiceRow("Upscaling filter", s.scaling, ScalingFilter.entries, { it.label.substringBefore(" (") }, describe = {
                        when (it) {
                            ScalingFilter.NEAREST -> "Sharp, blocky pixels"
                            ScalingFilter.BILINEAR -> "Soft and smooth"
                            ScalingFilter.BICUBIC -> "Sharper smoothing (experimental)"
                            ScalingFilter.LANCZOS3 -> "Sharpest smoothing (experimental)"
                            ScalingFilter.XBRZ -> "Pixel-art upscaler: rounded, clean edges (experimental)"
                        }
                    }) { v -> onChange { it.copy(scaling = v) } }
                    if (s.scaling == ScalingFilter.XBRZ) {
                        SliderRow("xBRZ factor", s.xbrzFactor.toFloat(), 2f..6f, steps = 3, format = { "${it.toInt()}x" }) { v -> onChange { it.copy(xbrzFactor = v.toInt()) } }
                    }
                    if (s.scaling == ScalingFilter.BICUBIC) {
                        SliderRow("Bicubic sharpness", s.bicubicSharpness.toFloat(), 0f..100f, format = { "${it.toInt()}" }) { v -> onChange { it.copy(bicubicSharpness = v.toInt()) } }
                    }
                    ChoiceRow("Shader", s.shader, listOf("none") + shaders.map { it.id },
                        { id -> if (id == "none") "None" else shaders.firstOrNull { it.id == id }?.title?.substringBefore(" —") ?: id },
                        describe = { id -> if (id == "none") "The picture as rendered" else shaders.firstOrNull { it.id == id }?.title?.substringAfter("— ", "") }) { v -> onChange { it.copy(shader = v) } }
                    if (s.shader != "none") {
                        SliderRow("Shader intensity", s.shaderIntensity, 0f..2f) { v -> onChange { it.copy(shaderIntensity = v) } }
                    }
                    SliderRow("Internal resolution", s.internalResolution, 1f..4f, steps = 5, format = { "%.1fx".format(it) },
                        subtitle = "Renders larger before scaling to the screen") { v -> onChange { it.copy(internalResolution = v) } }
                    SwitchRow("Hi-res texture packs", s.hiresTextures, "Loads Hires/ replacements when the game ships them") { v -> onChange { it.copy(hiresTextures = v) } }
                }
            }
        }
        SettingsCategory.GAMEPLAY -> {
            Section("Dialogue") {
                SwitchRow("Instant text", s.instantText, "Messages appear at once instead of letter by letter. Pauses and button prompts still work (Pokémon Essentials)") { v -> onChange { it.copy(instantText = v) } }
            }
            Section("Map") {
                SwitchRow("Minimap", s.minimap, "A small map of the area in the top-right corner: walkable ground, water, grass and you") { v -> onChange { it.copy(minimap = v) } }
            }
            Section("Pokémon") {
                ChoiceRow("Shiny odds", s.shinyOdds, listOf(0, 512, 256, 128), { if (it == 0) "Game default" else "1 in $it" },
                    "For Pokémon met from now on. Your own Pokémon stay as they are (Pokémon Essentials)",
                    describe = { if (it == 0) "Whatever the game uses (often 1 in 8192 or 4096)" else "Added on top of the game's own chance" }) { v -> onChange { it.copy(shinyOdds = v) } }
            }
        }
        SettingsCategory.PERFORMANCE -> {
            Section("Rendering") {
                SwitchRow("GPU map renderer", s.gpuMaps, "Draws maps on the GPU (Pokémon Essentials). Turn off if map tiles look wrong") { v -> onChange { it.copy(gpuMaps = v) } }
                SwitchRow("60 FPS (RPG Maker XP)", s.force60, "Runs 40 FPS games at 60. Essentials keeps walking speed; some animations and text play faster") { v -> onChange { it.copy(force60 = v) } }
                SwitchRow("VSync", s.vsync, "Used only when the screen can show the game's frame rate evenly") { v -> onChange { it.copy(vsync = v) } }
                SwitchRow("Frame skip when slow", s.frameSkip) { v -> onChange { it.copy(frameSkip = v) } }
                ChoiceRow("Frame-rate cap", s.fixedFramerate, listOf(0, 30, 40, 60, 120), { if (it == 0) "Game default" else "$it FPS" }) { v -> onChange { it.copy(fixedFramerate = v) } }
            }
            Section("Loading") {
                SwitchRow("Graphics cache", s.graphicsCache, "Decodes character sprites in the background so they appear without a hitch. Uses more memory") { v -> onChange { it.copy(graphicsCache = v) } }
                SwitchRow("Stream maps into RAM", s.mapCache, "Map transfers decode from memory instead of storage") { v -> onChange { it.copy(mapCache = v) } }
                if (s.mapCache) SliderRow("Map cache budget", s.mapCacheMb.toFloat(), 32f..512f, format = { "${it.toInt()} MB" }) { v -> onChange { it.copy(mapCacheMb = v.toInt()) } }
                SwitchRow("Warm up graphics", s.warmGraphics, "Pre-reads tilesets and characters in the background") { v -> onChange { it.copy(warmGraphics = v) } }
                SwitchRow("Optimized maps (experimental)", s.optimizedMaps, "Per-map compact tilesets written to disk. Some scripted games break") { v -> onChange { it.copy(optimizedMaps = v) } }
            }
        }
        SettingsCategory.SPEED -> {
            Section("Fast-forward") {
                ChoiceRow("Method", s.turboMode, TurboMode.entries, { it.label }, describe = {
                    when (it) {
                        TurboMode.FRAMERATE -> "Runs the game faster; smooth, needs headroom"
                        TurboMode.FRAMESKIP -> "Keeps up on heavy maps; some scripted scenes can desync"
                        TurboMode.HYBRID -> "Both, for the highest speeds"
                    }
                }) { v -> onChange { it.copy(turboMode = v) } }
                SliderRow("Speed", s.turboSpeed.toFloat(), 2f..8f, steps = 5, format = { "${it.toInt()}x" }) { v -> onChange { it.copy(turboSpeed = v.toInt()) } }
                SwitchRow("Toggle instead of hold", s.turboToggle) { v -> onChange { it.copy(turboToggle = v) } }
            }
        }
        SettingsCategory.INPUT -> {
            Section("Touch") {
                SwitchRow("Touch controls", s.showTouchControls) { v -> onChange { it.copy(showTouchControls = v) } }
                SliderRow("Touch opacity", s.touchOpacity, 0.1f..1f, format = { "${(it * 100).toInt()}%" }) { v -> onChange { it.copy(touchOpacity = v) } }
                SwitchRow("Vibration", s.vibration) { v -> onChange { it.copy(vibration = v) } }
            }
            Section("Controller") {
                ChoiceRow("Layout", s.controllerProfile, ControllerProfile.entries, { it.label.substringBefore(" (") },
                    describe = { it.label.substringAfter("(", "").removeSuffix(")") }) { v -> onChange { it.copy(controllerProfile = v) } }
                SliderRow("Autofire rate", s.autofireRateHz.toFloat(), 4f..30f, format = { "${it.toInt()} Hz" }) { v -> onChange { it.copy(autofireRateHz = v.toInt()) } }
            }
            Section("Overlay") {
                SwitchRow("FPS, clock & battery", s.showInfo, "The longest frame of the last second is shown next to the FPS") { v -> onChange { it.copy(showInfo = v) } }
                SwitchRow("Engine FPS counter", s.showEngineFps) { v -> onChange { it.copy(showEngineFps = v) } }
            }
        }
        SettingsCategory.AUDIO -> {
            Section("MIDI") {
                ActionRow("SoundFont", "Many RPG Maker XP games use MIDI music; an .sf2 decides how it sounds",
                    value = s.soundFont.takeIf { it.isNotBlank() }?.let { File(it).name } ?: "Built-in") { pickSf2.launch(arrayOf("*/*")) }
                SwitchRow("Reverb", s.midiReverb) { v -> onChange { it.copy(midiReverb = v) } }
                SwitchRow("Chorus", s.midiChorus) { v -> onChange { it.copy(midiChorus = v) } }
            }
        }
        SettingsCategory.COMPAT -> {
            Section("Engine") {
                ChoiceRow("RGSS version", s.rgssVersionOverride, listOf(0, 1, 2, 3),
                    { when (it) { 0 -> "Auto"; 1 -> "XP (RGSS1)"; 2 -> "VX (RGSS2)"; else -> "VX Ace (RGSS3)" } },
                    describe = { if (it == 0) "Detected from the game's files" else "Only if detection picks the wrong one" }) { v -> onChange { it.copy(rgssVersionOverride = v) } }
                SliderRow("Font scale", s.fontScale, 0f..1.5f, format = { if (it < 0.05f) "Auto" else "%.2f".format(it) }) { v -> onChange { it.copy(fontScale = if (v < 0.05f) 0f else v) } }
            }
            Section("Saves") {
                SwitchRow("Keep saves in Yami", s.redirectSaves, "New save files go to Yami's folder; old saves still load") { v -> onChange { it.copy(redirectSaves = v) } }
            }
        }
    }
}
