package com.lordnordyx.yami.input

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import com.lordnordyx.yami.data.ControllerProfile
import kotlin.math.abs

/**
 * Automatic controller binding. Any device Android classifies as a gamepad or
 * joystick is bound without setup: the profile is picked from the vendor id
 * (Nintendo pads get the A/B swap their labels imply), sticks and hats drive
 * the directions, triggers work whether they report as keys or axes, and user
 * remaps from the Controls screen are layered on top.
 */
class ControllerMapper(
    private val injector: KeyInjector,
    private var config: InputConfig,
    private val forcedProfile: ControllerProfile,
) {
    data class Connected(val id: Int, val name: String, val profile: ControllerProfile)

    private val profiles = HashMap<Int, ControllerProfile>()
    /** Per device: which directions each analog source is currently holding. */
    private val axisHeld = HashMap<Int, MutableMap<String, RgssButton?>>()

    var onControllerSeen: ((Connected) -> Unit)? = null

    fun updateConfig(c: InputConfig) { config = c }

    fun profileFor(dev: InputDevice?): ControllerProfile {
        if (forcedProfile != ControllerProfile.AUTO) return forcedProfile
        dev ?: return ControllerProfile.XBOX
        return profiles.getOrPut(dev.id) {
            val p = detect(dev)
            onControllerSeen?.invoke(Connected(dev.id, dev.name, p))
            p
        }
    }

    private fun detect(dev: InputDevice): ControllerProfile {
        val name = dev.name.lowercase()
        return when {
            dev.vendorId == 0x057E || "nintendo" in name || "pro controller" in name || "joy-con" in name -> ControllerProfile.NINTENDO
            dev.vendorId == 0x054C || "dualsense" in name || "dualshock" in name || "wireless controller" in name -> ControllerProfile.PLAYSTATION
            else -> ControllerProfile.XBOX
        }
    }

    /** Positional defaults (Android reports the bottom face button as BUTTON_A). */
    private fun defaultFor(keyCode: Int, p: ControllerProfile): RgssButton? {
        val nintendo = p == ControllerProfile.NINTENDO
        return when (keyCode) {
            KeyEvent.KEYCODE_BUTTON_A -> if (nintendo) RgssButton.B else RgssButton.C
            KeyEvent.KEYCODE_BUTTON_B -> if (nintendo) RgssButton.C else RgssButton.B
            KeyEvent.KEYCODE_BUTTON_X -> if (nintendo) RgssButton.X else RgssButton.A
            KeyEvent.KEYCODE_BUTTON_Y -> if (nintendo) RgssButton.A else RgssButton.X
            KeyEvent.KEYCODE_BUTTON_L1 -> RgssButton.L
            KeyEvent.KEYCODE_BUTTON_R1 -> RgssButton.R
            KeyEvent.KEYCODE_BUTTON_L2 -> config.triggersAs.first
            KeyEvent.KEYCODE_BUTTON_R2 -> config.triggersAs.second
            KeyEvent.KEYCODE_BUTTON_THUMBL -> RgssButton.Y
            KeyEvent.KEYCODE_BUTTON_THUMBR -> RgssButton.Z
            KeyEvent.KEYCODE_BUTTON_START -> RgssButton.B      // RGSS opens its menu with cancel
            KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_MODE -> RgssButton.MENU
            KeyEvent.KEYCODE_BACK -> RgssButton.B              // some pads send BACK for B
            KeyEvent.KEYCODE_DPAD_UP -> RgssButton.UP
            KeyEvent.KEYCODE_DPAD_DOWN -> RgssButton.DOWN
            KeyEvent.KEYCODE_DPAD_LEFT -> RgssButton.LEFT
            KeyEvent.KEYCODE_DPAD_RIGHT -> RgssButton.RIGHT
            KeyEvent.KEYCODE_DPAD_CENTER -> RgssButton.C
            else -> null
        }
    }

    fun resolve(keyCode: Int, p: ControllerProfile): RgssButton? =
        config.remaps[p.name]?.get(keyCode) ?: defaultFor(keyCode, p)

    /** @return true if consumed. */
    fun onKey(e: KeyEvent): Boolean {
        if (!isController(e.device, e.source)) return false
        val b = resolve(e.keyCode, profileFor(e.device)) ?: return false
        when (e.action) {
            KeyEvent.ACTION_DOWN -> if (e.repeatCount == 0) injector.press(b)
            KeyEvent.ACTION_UP -> injector.release(b)
        }
        return true
    }

    fun onMotion(e: MotionEvent): Boolean {
        if (e.source and InputDevice.SOURCE_JOYSTICK != InputDevice.SOURCE_JOYSTICK) return false
        if (e.action != MotionEvent.ACTION_MOVE) return false
        val held = axisHeld.getOrPut(e.deviceId) { HashMap() }
        val dz = config.stickDeadzone

        // Hat (most d-pads) and left stick share the direction buttons.
        axisPair(held, "hatX", e.getAxisValue(MotionEvent.AXIS_HAT_X), 0.5f, RgssButton.LEFT, RgssButton.RIGHT)
        axisPair(held, "hatY", e.getAxisValue(MotionEvent.AXIS_HAT_Y), 0.5f, RgssButton.UP, RgssButton.DOWN)
        axisPair(held, "lx", e.getAxisValue(MotionEvent.AXIS_X), dz, RgssButton.LEFT, RgssButton.RIGHT)
        axisPair(held, "ly", e.getAxisValue(MotionEvent.AXIS_Y), dz, RgssButton.UP, RgssButton.DOWN)
        if (config.rightStickAsDpad) {
            axisPair(held, "rx", e.getAxisValue(MotionEvent.AXIS_Z), dz, RgssButton.LEFT, RgssButton.RIGHT)
            axisPair(held, "ry", e.getAxisValue(MotionEvent.AXIS_RZ), dz, RgssButton.UP, RgssButton.DOWN)
        }
        // Analog triggers (pads that don't also send BUTTON_L2/R2 key events).
        val lt = maxOf(e.getAxisValue(MotionEvent.AXIS_LTRIGGER), e.getAxisValue(MotionEvent.AXIS_BRAKE))
        val rt = maxOf(e.getAxisValue(MotionEvent.AXIS_RTRIGGER), e.getAxisValue(MotionEvent.AXIS_GAS))
        trigger(held, "lt", lt, config.triggersAs.first)
        trigger(held, "rt", rt, config.triggersAs.second)
        return true
    }

    private fun axisPair(held: MutableMap<String, RgssButton?>, key: String, v: Float, dz: Float, neg: RgssButton, pos: RgssButton) {
        val want = when {
            v <= -dz -> neg
            v >= dz -> pos
            else -> null
        }
        val cur = held[key]
        if (cur == want) return
        cur?.let { injector.release(it) }
        want?.let { injector.press(it) }
        held[key] = want
    }

    private fun trigger(held: MutableMap<String, RgssButton?>, key: String, v: Float, b: RgssButton) {
        val want = if (abs(v) > 0.5f) b else null
        val cur = held[key]
        if (cur == want) return
        cur?.let { injector.release(it) }
        want?.let { injector.press(it) }
        held[key] = want
    }

    fun connected(): List<Connected> = InputDevice.getDeviceIds().toList()
        .mapNotNull { InputDevice.getDevice(it) }
        .filter { isController(it, it.sources) }
        .map { Connected(it.id, it.name, profileFor(it)) }

    companion object {
        fun isController(dev: InputDevice?, source: Int): Boolean {
            val pad = source and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD
            val joy = source and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
            if (!pad && !joy) return false
            return dev == null || !dev.isVirtual
        }
    }
}
