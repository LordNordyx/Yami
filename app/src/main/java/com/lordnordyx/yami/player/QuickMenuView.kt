package com.lordnordyx.yami.player

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.view.Gravity
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.res.ResourcesCompat
import com.lordnordyx.yami.R
import kotlin.math.abs

/**
 * In-game menu: glass over the game. Touch, d-pad (buttons, hat or stick)
 * and A/B all work; left/right change a value in place (Look).
 */
@SuppressLint("ViewConstructor")
class QuickMenuView(
    context: Context,
    private val accent: Int,
    private val onAction: (Action) -> Unit,
) : FrameLayout(context) {

    enum class Action {
        RESUME, LOOK_NEXT, LOOK_PREV, TURBO, INSTANT_TEXT, MINIMAP, TOUCH, EDIT_LAYOUT, RESET_LAYOUT, INFO,
        SCREENSHOT, LOG, SOFT_RESET, RESTART, QUIT,
    }

    data class State(val turbo: Boolean, val touchVisible: Boolean, val info: Boolean, val title: String,
                     val instantText: Boolean = false, val minimap: Boolean = false, val look: String = "")

    private class Item(val action: Action, val row: View, val label: TextView, val value: TextView?, val cycles: Boolean)

    private val items = ArrayList<Item>()
    private var selected = 0
    private val dp = resources.displayMetrics.density
    private val pixel: Typeface? = runCatching { ResourcesCompat.getFont(context, R.font.silkscreen) }.getOrNull()
    private val pixelTitle: Typeface? = runCatching { ResourcesCompat.getFont(context, R.font.pixelify_sans) }.getOrNull()
    private val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val scroll: ScrollView

    init {
        setBackgroundColor(0x99000000.toInt())           // the game stays visible through the dark
        isClickable = true
        setOnClickListener { onAction(Action.RESUME) }
        val glass = GradientDrawable().apply {
            cornerRadius = 26 * dp
            colors = intArrayOf(0xD016161E.toInt(), 0xE00A0A0E.toInt())   // a little light at the top
            orientation = GradientDrawable.Orientation.TOP_BOTTOM
            setStroke((1 * dp).toInt(), 0x30FFFFFF)
        }
        val edge = GradientDrawable().apply {                         // light catching the top edge
            cornerRadius = 26 * dp
            colors = intArrayOf(0x22FFFFFF, 0x00FFFFFF)
            orientation = GradientDrawable.Orientation.TOP_BOTTOM
            gradientType = GradientDrawable.LINEAR_GRADIENT
        }
        scroll = ScrollView(context).apply {
            background = LayerDrawable(arrayOf(glass, edge)).apply { setLayerSize(1, -1, (40 * dp).toInt()) }
            setPadding((10 * dp).toInt(), (10 * dp).toInt(), (10 * dp).toInt(), (10 * dp).toInt())
            isVerticalScrollBarEnabled = false
            addView(list)
            isClickable = true
        }
        addView(scroll, LayoutParams((340 * dp).toInt(), LayoutParams.WRAP_CONTENT, Gravity.CENTER).apply {
            topMargin = (16 * dp).toInt(); bottomMargin = (16 * dp).toInt()
        })
    }

    fun show(s: State) {
        list.removeAllViews()
        items.clear()
        // header: the game in the pixel face, YAMI small above it
        list.addView(TextView(context).apply {
            text = "YAMI"
            setTextColor(accent); textSize = 10f; letterSpacing = 0.25f
            typeface = pixel ?: Typeface.MONOSPACE
            setPadding((14 * dp).toInt(), (6 * dp).toInt(), (14 * dp).toInt(), 0)
        })
        list.addView(TextView(context).apply {
            text = s.title.ifBlank { "Paused" }
            setTextColor(0xFFECEAF2.toInt()); textSize = 20f
            typeface = pixelTitle ?: Typeface.DEFAULT
            maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding((14 * dp).toInt(), (2 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
        })
        add(Action.RESUME, "Resume")
        add(Action.LOOK_NEXT, "Look", "‹  ${s.look}  ›", cycles = true)
        add(Action.TURBO, "Speed-up", onOff(s.turbo))
        add(Action.INSTANT_TEXT, "Instant text", onOff(s.instantText))
        add(Action.MINIMAP, "Minimap", onOff(s.minimap))
        add(Action.TOUCH, "Touch controls", if (s.touchVisible) "shown" else "hidden")
        add(Action.EDIT_LAYOUT, "Edit touch layout")
        add(Action.RESET_LAYOUT, "Reset touch layout")
        add(Action.INFO, "FPS & clock", onOff(s.info))
        add(Action.SCREENSHOT, "Screenshot")
        add(Action.LOG, "Engine log")
        add(Action.SOFT_RESET, "Soft reset")
        add(Action.RESTART, "Restart game")
        add(Action.QUIT, "Quit to library")
        list.addView(TextView(context).apply {
            text = "A select · B back · ◀ ▶ change"
            setTextColor(0xFF4F4E5A.toInt()); textSize = 10f; letterSpacing = 0.05f
            typeface = pixel ?: Typeface.MONOSPACE
            gravity = Gravity.CENTER
            setPadding(0, (10 * dp).toInt(), 0, (4 * dp).toInt())
        })
        selected = selected.coerceIn(0, items.size - 1)
        highlight()
        visibility = View.VISIBLE
    }

    private fun onOff(b: Boolean) = if (b) "ON" else "off"

    private fun add(a: Action, label: String, value: String? = null, cycles: Boolean = false) {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((14 * dp).toInt(), (11 * dp).toInt(), (14 * dp).toInt(), (11 * dp).toInt())
            isClickable = true
        }
        val lt = TextView(context).apply {
            text = label
            setTextColor(0xFFECEAF2.toInt()); textSize = 16f
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        }
        row.addView(lt, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val vt = value?.let {
            TextView(context).apply {
                text = it
                setTextColor(if (it == "ON" || cycles) accent else 0xFF8C8B99.toInt())
                textSize = 13f
                typeface = pixel ?: Typeface.MONOSPACE
            }.also { v -> row.addView(v) }
        }
        val index = items.size
        row.setOnClickListener { selected = index; highlight(); onAction(a) }
        items += Item(a, row, lt, vt, cycles)
        list.addView(row)
    }

    private fun highlight() {
        items.forEachIndexed { i, it ->
            val on = i == selected
            it.row.background = if (on) GradientDrawable().apply {
                setColor((accent and 0x00FFFFFF) or 0x26000000); cornerRadius = 16 * dp
                setStroke((1 * dp).toInt(), (accent and 0x00FFFFFF) or 0x80000000.toInt())
            } else null
            it.label.setTextColor(if (on) accent else 0xFFECEAF2.toInt())
            if (on) scroll.post { scroll.smoothScrollTo(0, (it.row.top - it.row.height).coerceAtLeast(0)) }
        }
    }

    private fun move(d: Int) {
        if (items.isEmpty()) return
        selected = (selected + d + items.size) % items.size
        highlight()
    }

    private fun change(right: Boolean) {
        val it = items.getOrNull(selected) ?: return
        if (it.cycles) onAction(if (right) Action.LOOK_NEXT else Action.LOOK_PREV)
    }

    /** @return true if consumed. */
    fun handleKey(e: KeyEvent): Boolean {
        if (e.action != KeyEvent.ACTION_DOWN) return isNavKey(e.keyCode)
        when (e.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> move(-1)
            KeyEvent.KEYCODE_DPAD_DOWN -> move(1)
            KeyEvent.KEYCODE_DPAD_LEFT -> change(false)
            KeyEvent.KEYCODE_DPAD_RIGHT -> change(true)
            KeyEvent.KEYCODE_BUTTON_L1 -> move(-4)
            KeyEvent.KEYCODE_BUTTON_R1 -> move(4)
            KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_SPACE,
            KeyEvent.KEYCODE_BUTTON_X -> items.getOrNull(selected)?.let { onAction(it.action) }
            KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE,
            KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_BUTTON_MODE -> onAction(Action.RESUME)
            else -> return false
        }
        return true
    }

    private fun isNavKey(k: Int) = k in setOf(
        KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
        KeyEvent.KEYCODE_BUTTON_L1, KeyEvent.KEYCODE_BUTTON_R1, KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_BUTTON_B,
        KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_START,
        KeyEvent.KEYCODE_BUTTON_MODE,
    )

    // d-pads that report as a hat, and the left stick: one step per push
    private var lastX = 0
    private var lastY = 0

    /** @return true if consumed (always, while the menu is open). */
    fun handleMotion(e: MotionEvent): Boolean {
        if (e.source and InputDevice.SOURCE_JOYSTICK != InputDevice.SOURCE_JOYSTICK) return false
        fun dir(hat: Float, stick: Float): Int {
            val v = if (abs(hat) > 0.5f) hat else if (abs(stick) > 0.6f) stick else 0f
            return if (v < 0f) -1 else if (v > 0f) 1 else 0
        }
        val y = dir(e.getAxisValue(MotionEvent.AXIS_HAT_Y), e.getAxisValue(MotionEvent.AXIS_Y))
        val x = dir(e.getAxisValue(MotionEvent.AXIS_HAT_X), e.getAxisValue(MotionEvent.AXIS_X))
        if (y != lastY && y != 0) move(y)
        if (x != lastX && x != 0) change(x > 0)
        lastX = x
        lastY = y
        return true
    }
}
