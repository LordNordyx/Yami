package com.lordnordyx.yami.player

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** In-game overlay menu. Works with touch, d-pad/sticks, and A/B buttons. */
@SuppressLint("ViewConstructor")
class QuickMenuView(
    context: Context,
    private val accent: Int,
    private val onAction: (Action) -> Unit,
) : FrameLayout(context) {

    enum class Action { RESUME, TURBO, TOUCH, EDIT_LAYOUT, RESET_LAYOUT, INFO, SCREENSHOT, LOG, SOFT_RESET, RESTART, QUIT }

    data class State(val turbo: Boolean, val touchVisible: Boolean, val info: Boolean, val title: String)

    private val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val items = ArrayList<Pair<Action, TextView>>()
    private var selected = 0
    private val dp = resources.displayMetrics.density

    init {
        setBackgroundColor(0xCC000000.toInt())
        isClickable = true
        setOnClickListener { onAction(Action.RESUME) }
        val panel = ScrollView(context).apply {
            background = GradientDrawable().apply { setColor(0xF00E0E12.toInt()); cornerRadius = 18 * dp; setStroke((1 * dp).toInt(), 0x33FFFFFF) }
            setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
            addView(list)
            isClickable = true
        }
        addView(panel, LayoutParams((300 * dp).toInt(), LayoutParams.WRAP_CONTENT, Gravity.CENTER))
    }

    fun show(s: State) {
        list.removeAllViews()
        items.clear()
        list.addView(TextView(context).apply {
            text = s.title.ifBlank { "Yami" }
            setTextColor(0x99FFFFFF.toInt()); textSize = 13f; typeface = Typeface.MONOSPACE
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
        })
        add(Action.RESUME, "▶  Resume")
        add(Action.TURBO, if (s.turbo) "»  Speed-up: ON" else "»  Speed-up: off")
        add(Action.TOUCH, if (s.touchVisible) "◎  Hide touch controls" else "◎  Show touch controls")
        add(Action.EDIT_LAYOUT, "✥  Edit touch layout")
        add(Action.RESET_LAYOUT, "↺  Reset touch layout")
        add(Action.INFO, if (s.info) "ⓘ  Hide FPS / clock / battery" else "ⓘ  Show FPS / clock / battery")
        add(Action.SCREENSHOT, "▣  Screenshot")
        add(Action.LOG, "≣  Engine log")
        add(Action.SOFT_RESET, "⟲  Soft reset (title screen)")
        add(Action.RESTART, "⏻  Restart game")
        add(Action.QUIT, "✕  Quit to library")
        selected = 0
        highlight()
        visibility = View.VISIBLE
    }

    private fun add(a: Action, label: String) {
        val tv = TextView(context).apply {
            text = label
            setTextColor(0xFFFFFFFF.toInt()); textSize = 16f; typeface = Typeface.MONOSPACE
            setPadding((14 * dp).toInt(), (12 * dp).toInt(), (14 * dp).toInt(), (12 * dp).toInt())
            setOnClickListener { onAction(a) }
        }
        items += a to tv
        list.addView(tv)
    }

    private fun highlight() {
        items.forEachIndexed { i, (_, tv) ->
            tv.background = if (i == selected) GradientDrawable().apply { setColor(accent); alpha = 90; cornerRadius = 10 * dp } else null
        }
    }

    /** @return true if consumed. */
    fun handleKey(e: KeyEvent): Boolean {
        if (e.action != KeyEvent.ACTION_DOWN) return isNavKey(e.keyCode)
        when (e.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> { selected = (selected - 1 + items.size) % items.size; highlight() }
            KeyEvent.KEYCODE_DPAD_DOWN -> { selected = (selected + 1) % items.size; highlight() }
            KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_SPACE ->
                onAction(items[selected].first)
            KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE,
            KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_START -> onAction(Action.RESUME)
            else -> return false
        }
        return true
    }

    private fun isNavKey(k: Int) = k in setOf(
        KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_BACK,
        KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_START,
    )
}
