package com.lordnordyx.yami.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import com.lordnordyx.yami.data.AspectPreset
import com.lordnordyx.yami.data.ControllerProfile
import com.lordnordyx.yami.data.GameSettings
import com.lordnordyx.yami.data.ScalingFilter
import com.lordnordyx.yami.data.ScreenFit
import com.lordnordyx.yami.data.TurboMode
import com.lordnordyx.yami.data.WidescreenMode
import com.lordnordyx.yami.ui.ActionRow
import com.lordnordyx.yami.ui.ChoiceRow
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.Section
import com.lordnordyx.yami.ui.SliderRow
import com.lordnordyx.yami.ui.SwitchRow
import kotlinx.coroutines.launch
import java.io.File

/** Every engine option, grouped. Used for per-game settings and global defaults. */
@Composable
fun SettingsEditor(vm: LibraryViewModel, s: GameSettings, onChange: ((GameSettings) -> GameSettings) -> Unit) {
    val shaders = remember { vm.shaders() }
    val scope = rememberCoroutineScope()
    val pickSf2 = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch { vm.importSoundFont(uri)?.let { p -> onChange { it.copy(soundFont = p) } } }
    }

    Column {
        Section("Display") {
            ChoiceRow("Widescreen", s.widescreen, WidescreenMode.entries, { it.label }, s.widescreen.blurb) { v -> onChange { it.copy(widescreen = v) } }
            if (s.widescreen != WidescreenMode.OFF) {
                ChoiceRow("Aspect ratio", s.aspect, AspectPreset.entries, { it.label }) { v -> onChange { it.copy(aspect = v) } }
            }
            ChoiceRow("Screen fit", s.fit, ScreenFit.entries, { it.label }) { v -> onChange { it.copy(fit = v) } }
            ChoiceRow("Upscaling filter", s.scaling, ScalingFilter.entries, { it.label }) { v -> onChange { it.copy(scaling = v) } }
            if (s.scaling == ScalingFilter.XBRZ) {
                SliderRow("xBRZ factor", s.xbrzFactor.toFloat(), 2f..6f, steps = 3, format = { "${it.toInt()}x" }) { v -> onChange { it.copy(xbrzFactor = v.toInt()) } }
            }
            if (s.scaling == ScalingFilter.BICUBIC) {
                SliderRow("Bicubic sharpness", s.bicubicSharpness.toFloat(), 0f..100f, format = { "${it.toInt()}" }) { v -> onChange { it.copy(bicubicSharpness = v.toInt()) } }
            }
            ChoiceRow("Shader", s.shader, listOf("none") + shaders.map { it.id },
                { id -> if (id == "none") "None" else shaders.firstOrNull { it.id == id }?.title?.substringBefore(" —") ?: id },
                subtitle = shaders.firstOrNull { it.id == s.shader }?.title?.substringAfter("— ", "")) { v -> onChange { it.copy(shader = v) } }
            if (s.shader != "none") {
                SliderRow("Shader intensity", s.shaderIntensity, 0f..2f) { v -> onChange { it.copy(shaderIntensity = v) } }
            }
            SliderRow("Internal resolution", s.internalResolution, 1f..4f, steps = 5, format = { "%.1fx".format(it) }) { v -> onChange { it.copy(internalResolution = v) } }
            SwitchRow("Hi-res texture packs", s.hiresTextures, "Loads Hires/ replacements when the game ships them") { v -> onChange { it.copy(hiresTextures = v) } }
        }
        Section("Speed-up") {
            ChoiceRow("Method", s.turboMode, TurboMode.entries, { it.label },
                "Frame skip keeps up better on heavy maps; some scripted scenes can desync") { v -> onChange { it.copy(turboMode = v) } }
            SliderRow("Speed", s.turboSpeed.toFloat(), 2f..8f, steps = 5, format = { "${it.toInt()}x" }) { v -> onChange { it.copy(turboSpeed = v.toInt()) } }
            SwitchRow("Toggle (instead of hold)", s.turboToggle) { v -> onChange { it.copy(turboToggle = v) } }
        }
        Section("Performance") {
            SwitchRow("Stream maps into RAM", s.mapCache, "Map transfers decode from memory instead of storage") { v -> onChange { it.copy(mapCache = v) } }
            if (s.mapCache) SliderRow("Map cache budget", s.mapCacheMb.toFloat(), 32f..512f, format = { "${it.toInt()} MB" }) { v -> onChange { it.copy(mapCacheMb = v.toInt()) } }
            SwitchRow("Optimized maps (experimental)", s.optimizedMaps, "Per-map compact tilesets for huge tilesets (RMXP). Some scripted games break — off by default") { v -> onChange { it.copy(optimizedMaps = v) } }
            SwitchRow("GPU map renderer", s.gpuMaps, "Smooth scrolling (Pokémon Essentials). Turn off if map tiles look wrong") { v -> onChange { it.copy(gpuMaps = v) } }
            SwitchRow("Graphics cache", s.graphicsCache, "Decodes character sprites in the background so they appear without a hitch. Uses more memory") { v -> onChange { it.copy(graphicsCache = v) } }
            SwitchRow("Warm up graphics", s.warmGraphics, "Pre-reads tilesets and characters in the background") { v -> onChange { it.copy(warmGraphics = v) } }
            SwitchRow("VSync", s.vsync) { v -> onChange { it.copy(vsync = v) } }
            SwitchRow("Frame skip when slow", s.frameSkip) { v -> onChange { it.copy(frameSkip = v) } }
            ChoiceRow("Frame-rate cap", s.fixedFramerate, listOf(0, 30, 40, 60, 120), { if (it == 0) "Game default" else "$it fps" }) { v -> onChange { it.copy(fixedFramerate = v) } }
        }
        Section("Overlay & input") {
            SwitchRow("Touch controls", s.showTouchControls) { v -> onChange { it.copy(showTouchControls = v) } }
            SliderRow("Touch opacity", s.touchOpacity, 0.1f..1f, format = { "${(it * 100).toInt()}%" }) { v -> onChange { it.copy(touchOpacity = v) } }
            SwitchRow("FPS / clock / battery", s.showInfo) { v -> onChange { it.copy(showInfo = v) } }
            SwitchRow("Vibration", s.vibration) { v -> onChange { it.copy(vibration = v) } }
            ChoiceRow("Controller layout", s.controllerProfile, ControllerProfile.entries, { it.label }) { v -> onChange { it.copy(controllerProfile = v) } }
            SliderRow("Autofire rate", s.autofireRateHz.toFloat(), 4f..30f, format = { "${it.toInt()} Hz" }) { v -> onChange { it.copy(autofireRateHz = v.toInt()) } }
        }
        Section("Audio") {
            ActionRow("MIDI SoundFont", "Many RMXP games use MIDI music; pick an .sf2 for best sound",
                value = s.soundFont.takeIf { it.isNotBlank() }?.let { File(it).name } ?: "Built-in") { pickSf2.launch(arrayOf("*/*")) }
            SwitchRow("MIDI reverb", s.midiReverb) { v -> onChange { it.copy(midiReverb = v) } }
            SwitchRow("MIDI chorus", s.midiChorus) { v -> onChange { it.copy(midiChorus = v) } }
        }
        Section("Compatibility") {
            ChoiceRow("RGSS version", s.rgssVersionOverride, listOf(0, 1, 2, 3),
                { when (it) { 0 -> "Auto"; 1 -> "XP (RGSS1)"; 2 -> "VX (RGSS2)"; else -> "VX Ace (RGSS3)" } }) { v -> onChange { it.copy(rgssVersionOverride = v) } }
            SliderRow("Font scale", s.fontScale, 0f..1.5f, format = { if (it < 0.05f) "Auto" else "%.2f".format(it) }) { v -> onChange { it.copy(fontScale = if (v < 0.05f) 0f else v) } }
            SwitchRow("Keep saves in Yami", s.redirectSaves, "New SaveN.rxdata go to Yami's folder; old saves still load") { v -> onChange { it.copy(redirectSaves = v) } }
            SwitchRow("Show engine FPS counter", s.showEngineFps) { v -> onChange { it.copy(showEngineFps = v) } }
        }
    }
}
