package com.lordnordyx.yami.input

import android.os.Handler
import android.os.Looper
import org.libsdl.app.SDLActivity

/**
 * Merges every input source (touch, controllers, remaps) into one press state
 * per RGSS button and forwards edges to SDL as key events. Reference counting
 * means a button held on two sources only releases when both let go.
 * Autofire re-pulses chosen buttons while held (never directions).
 */
class KeyInjector(private val onFrontendAction: (RgssButton, Boolean) -> Unit) {

    private val counts = IntArray(RgssButton.values().size)
    private val handler = Handler(Looper.getMainLooper())
    var autofire: Set<RgssButton> = emptySet()
    var autofireHz: Int = 12
    private val autofireHeld = HashSet<RgssButton>()
    private var pulseDown = false

    private val pulse = object : Runnable {
        override fun run() {
            if (autofireHeld.isEmpty()) return
            pulseDown = !pulseDown
            autofireHeld.forEach { send(it, pulseDown) }
            handler.postDelayed(this, (500L / autofireHz.coerceIn(2, 30)))
        }
    }

    @Synchronized
    fun press(b: RgssButton) {
        if (b == RgssButton.NONE) return
        val i = b.ordinal
        counts[i]++
        if (counts[i] != 1) return
        if (!b.sendsKey) { onFrontendAction(b, true); return }
        send(b, true)
        if (b in autofire && !b.directional) {
            val start = autofireHeld.isEmpty()
            autofireHeld += b
            if (start) { pulseDown = true; handler.postDelayed(pulse, 500L / autofireHz.coerceIn(2, 30)) }
        }
    }

    @Synchronized
    fun release(b: RgssButton) {
        if (b == RgssButton.NONE) return
        val i = b.ordinal
        if (counts[i] == 0) return
        counts[i]--
        if (counts[i] != 0) return
        if (!b.sendsKey) { onFrontendAction(b, false); return }
        autofireHeld -= b
        send(b, false)
    }

    fun set(b: RgssButton, down: Boolean) = if (down) press(b) else release(b)

    fun isDown(b: RgssButton) = counts[b.ordinal] > 0

    /** One-shot tap (menu actions like soft reset). */
    fun tap(b: RgssButton) {
        send(b, true)
        handler.postDelayed({ send(b, false) }, 80)
    }

    @Synchronized
    fun releaseAll() {
        RgssButton.values().forEach { b -> while (counts[b.ordinal] > 0) release(b) }
        autofireHeld.clear()
    }

    private fun send(b: RgssButton, down: Boolean) {
        if (!b.sendsKey) return
        try {
            if (down) SDLActivity.onNativeKeyDown(b.keycode) else SDLActivity.onNativeKeyUp(b.keycode)
        } catch (_: UnsatisfiedLinkError) {
            // engine not loaded yet
        }
    }
}
