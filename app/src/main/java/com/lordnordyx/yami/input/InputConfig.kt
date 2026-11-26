package com.lordnordyx.yami.input

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/** Touch element kinds that can be placed on screen. */
@Serializable
enum class TouchKind { DPAD, STICK, BUTTON }

@Serializable
data class TouchElement(
    val id: String,
    val kind: TouchKind,
    val button: RgssButton = RgssButton.NONE,
    val label: String = "",
    /** Center, as a fraction of the overlay's width/height. */
    val cx: Float,
    val cy: Float,
    /** Diameter as a fraction of the overlay's shorter side. */
    val size: Float,
    val visible: Boolean = true,
)

@Serializable
data class TouchLayout(
    val elements: List<TouchElement> = defaultElements(),
    /** Floating analog: the stick spawns wherever the left thumb lands. */
    val floatingStick: Boolean = true,
    val hideWithController: Boolean = true,
) {
    companion object {
        fun defaultElements() = listOf(
            TouchElement("move", TouchKind.STICK, cx = 0.13f, cy = 0.72f, size = 0.38f),
            TouchElement("c", TouchKind.BUTTON, RgssButton.C, "C", 0.91f, 0.70f, 0.17f),
            TouchElement("b", TouchKind.BUTTON, RgssButton.B, "B", 0.80f, 0.84f, 0.15f),
            TouchElement("a", TouchKind.BUTTON, RgssButton.A, "A", 0.80f, 0.56f, 0.13f),
            TouchElement("x", TouchKind.BUTTON, RgssButton.X, "X", 0.69f, 0.88f, 0.10f, visible = false),
            TouchElement("z", TouchKind.BUTTON, RgssButton.Z, "Z", 0.91f, 0.45f, 0.10f, visible = false),
            TouchElement("l", TouchKind.BUTTON, RgssButton.L, "L", 0.06f, 0.10f, 0.11f),
            TouchElement("r", TouchKind.BUTTON, RgssButton.R, "R", 0.94f, 0.10f, 0.11f),
            TouchElement("turbo", TouchKind.BUTTON, RgssButton.TURBO, "»", 0.20f, 0.10f, 0.10f),
            TouchElement("menu", TouchKind.BUTTON, RgssButton.MENU, "≡", 0.50f, 0.06f, 0.09f),
        )
    }
}

@Serializable
data class InputConfig(
    /** Android keycode → RGSS button overrides, per controller profile name. */
    val remaps: Map<String, Map<Int, RgssButton>> = emptyMap(),
    val autofire: Set<RgssButton> = emptySet(),
    val stickDeadzone: Float = 0.35f,
    val rightStickAsDpad: Boolean = false,
    val triggersAs: Pair<RgssButton, RgssButton> = RgssButton.TURBO to RgssButton.Z,
    val touch: TouchLayout = TouchLayout(),
) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; allowStructuredMapKeys = true }
        private fun file(ctx: Context) = File(ctx.filesDir, "input.json")

        fun load(ctx: Context): InputConfig =
            runCatching { json.decodeFromString<InputConfig>(file(ctx).readText()) }.getOrDefault(InputConfig())

        fun save(ctx: Context, cfg: InputConfig) {
            val f = file(ctx)
            val tmp = File(f.parentFile, "input.json.tmp")
            tmp.writeText(json.encodeToString(cfg))
            tmp.renameTo(f)
        }
    }
}
