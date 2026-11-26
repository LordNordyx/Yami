package com.lordnordyx.yami.input

import android.view.KeyEvent
import kotlinx.serialization.Serializable

/**
 * Logical RGSS inputs. Each is delivered to the engine as a keyboard key that
 * mkxp-z binds by default for every RGSS version (see keybindings.cpp), so no
 * engine-side binding file is needed and the player's keyboard still works.
 */
@Serializable
enum class RgssButton(val label: String, val keycode: Int, val directional: Boolean = false) {
    UP("Up", KeyEvent.KEYCODE_DPAD_UP, true),
    DOWN("Down", KeyEvent.KEYCODE_DPAD_DOWN, true),
    LEFT("Left", KeyEvent.KEYCODE_DPAD_LEFT, true),
    RIGHT("Right", KeyEvent.KEYCODE_DPAD_RIGHT, true),
    C("C · Confirm", KeyEvent.KEYCODE_SPACE),
    B("B · Cancel / Menu", KeyEvent.KEYCODE_X),
    A("A · Action", KeyEvent.KEYCODE_SHIFT_LEFT),
    X("X", KeyEvent.KEYCODE_A),
    Y("Y", KeyEvent.KEYCODE_S),
    Z("Z", KeyEvent.KEYCODE_D),
    L("L · Page up", KeyEvent.KEYCODE_Q),
    R("R · Page down", KeyEvent.KEYCODE_W),
    CTRL("Ctrl", KeyEvent.KEYCODE_CTRL_LEFT),
    ALT("Alt", KeyEvent.KEYCODE_ALT_LEFT),
    F5("F5", KeyEvent.KEYCODE_F5),
    F6("F6", KeyEvent.KEYCODE_F6),
    F7("F7", KeyEvent.KEYCODE_F7),
    F8("F8", KeyEvent.KEYCODE_F8),
    F9("F9", KeyEvent.KEYCODE_F9),
    TURBO("Speed-up", KeyEvent.KEYCODE_F10),
    RESET("Soft reset", KeyEvent.KEYCODE_F12),
    /** Frontend-only: opens Yami's quick menu, never sent to the engine. */
    MENU("Yami menu", 0),
    NONE("Unbound", 0);

    val sendsKey get() = keycode != 0
}
