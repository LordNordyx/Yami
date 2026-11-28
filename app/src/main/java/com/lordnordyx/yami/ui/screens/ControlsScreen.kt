package com.lordnordyx.yami.ui.screens

import android.view.KeyEvent
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.lordnordyx.yami.data.ControllerProfile
import com.lordnordyx.yami.input.ControllerMapper
import com.lordnordyx.yami.input.InputConfig
import com.lordnordyx.yami.input.KeyInjector
import com.lordnordyx.yami.input.RgssButton
import com.lordnordyx.yami.ui.ActionRow
import com.lordnordyx.yami.ui.ChoiceRow
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.Section
import com.lordnordyx.yami.ui.SliderRow
import com.lordnordyx.yami.ui.SwitchRow
import com.lordnordyx.yami.ui.YamiTopBar
import com.lordnordyx.yami.ui.theme.Dark
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.navigationBarsPadding

private val REMAPPABLE = listOf(
    RgssButton.C, RgssButton.B, RgssButton.A, RgssButton.X, RgssButton.Y, RgssButton.Z,
    RgssButton.L, RgssButton.R, RgssButton.CTRL, RgssButton.F5, RgssButton.F9, RgssButton.TURBO, RgssButton.MENU,
)

@Composable
fun ControlsScreen(vm: LibraryViewModel, back: () -> Unit) {
    val ctx = LocalContext.current
    var cfg by remember { mutableStateOf(InputConfig.load(ctx)) }
    fun save(c: InputConfig) { cfg = c; InputConfig.save(ctx, c) }

    // Mapper used only to resolve names/profiles for display; never injects here.
    val mapper = remember(cfg) { ControllerMapper(KeyInjector { _, _ -> }, cfg, ControllerProfile.AUTO) }
    val pads = remember(cfg) { mapper.connected() }
    var profile by remember { mutableStateOf(pads.firstOrNull()?.profile ?: ControllerProfile.XBOX) }
    var lastInput by remember { mutableStateOf("Press any button on your controller") }
    var capture by remember { mutableStateOf<RgssButton?>(null) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    Column(Modifier.fillMaxSize()) {
    YamiTopBar("Controls", back)
    Column(
        Modifier.fillMaxSize().navigationBarsPadding().focusRequester(focus).focusable()
            .onPreviewKeyEvent { ke ->
                val e = ke.nativeKeyEvent
                if (!ControllerMapper.isController(e.device, e.source) || e.action != KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
                val target = capture
                if (target != null) {
                    val profMap = (cfg.remaps[profile.name] ?: emptyMap()).filterValues { it != target } + (e.keyCode to target)
                    save(cfg.copy(remaps = cfg.remaps + (profile.name to profMap)))
                    capture = null
                } else {
                    val b = mapper.resolve(e.keyCode, profile)
                    lastInput = "${KeyEvent.keyCodeToString(e.keyCode).removePrefix("KEYCODE_")}  →  ${b?.label ?: "unbound"}"
                }
                true
            }
            .verticalScroll(rememberScrollState()),
    ) {
        capture?.let { b ->
            Section("Binding") {
                ActionRow("Press the controller button for ${b.label}", "Tap here to cancel") { capture = null }
            }
        }

        Section("Controllers") {
            if (pads.isEmpty()) ActionRow("No controller connected", "Bluetooth and USB pads are bound automatically when they connect")
            pads.forEach { p -> ActionRow(p.name, "Detected layout: ${p.profile.label}") }
            Text(lastInput, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 14.dp))
        }

        Section("Button mapping") {
            ChoiceRow("Edit layout for", profile, ControllerProfile.entries.filter { it != ControllerProfile.AUTO }, { it.label }) { profile = it }
            REMAPPABLE.forEach { b ->
                val keys = (cfg.remaps[profile.name] ?: emptyMap()).filterValues { it == b }.keys
                val label = if (keys.isEmpty()) "default" else keys.joinToString { KeyEvent.keyCodeToString(it).removePrefix("KEYCODE_BUTTON_").removePrefix("KEYCODE_") }
                ActionRow(b.label, value = label) { capture = b }
            }
            ActionRow("Reset this layout") { save(cfg.copy(remaps = cfg.remaps - profile.name)) }
        }

        Section("Autofire") {
            listOf(RgssButton.C, RgssButton.B, RgssButton.A, RgssButton.X).forEach { b ->
                SwitchRow("Autofire ${b.label}", b in cfg.autofire) { on ->
                    save(cfg.copy(autofire = if (on) cfg.autofire + b else cfg.autofire - b))
                }
            }
        }

        Section("Sticks & triggers") {
            SliderRow("Stick deadzone", cfg.stickDeadzone, 0.1f..0.8f, format = { "${(it * 100).toInt()}%" }) { save(cfg.copy(stickDeadzone = it)) }
            SwitchRow("Right stick moves too", cfg.rightStickAsDpad) { save(cfg.copy(rightStickAsDpad = it)) }
            val trig = listOf(RgssButton.TURBO, RgssButton.Z, RgssButton.Y, RgssButton.L, RgssButton.R, RgssButton.A, RgssButton.NONE)
            ChoiceRow("Left trigger", cfg.triggersAs.first, trig, { it.label }) { save(cfg.copy(triggersAs = it to cfg.triggersAs.second)) }
            ChoiceRow("Right trigger", cfg.triggersAs.second, trig, { it.label }) { save(cfg.copy(triggersAs = cfg.triggersAs.first to it)) }
        }

        Section("Touch") {
            SwitchRow("Floating analog stick", cfg.touch.floatingStick, "Stick appears wherever your left thumb lands") {
                save(cfg.copy(touch = cfg.touch.copy(floatingStick = it)))
            }
            SwitchRow("Hide when a controller is used", cfg.touch.hideWithController) {
                save(cfg.copy(touch = cfg.touch.copy(hideWithController = it)))
            }
            ActionRow("Customize layout", "In game: ≡ menu → Edit touch layout (drag, double-tap to resize, hold to hide)")
        }
        Spacer(Modifier.height(48.dp))
    }
    }
}
