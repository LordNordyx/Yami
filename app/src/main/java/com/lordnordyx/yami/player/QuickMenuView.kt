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

    enum class Action {
        RESUME, TURBO, TOUCH, EDIT_LAYOUT, RESET_LAYOUT, INFO, SCREENSHOT, LOG, SOFT_RESET, RESTART, QUIT,
        INSTANT_TEXT, MINIMAP, CHEATS,
        CHEAT_SHINY, CHEAT_ENCOUNTERS, CHEAT_NOCLIP, CHEAT_MONEY, CHEAT_HEAL, BACK,
    }

    data class State(val turbo: Boolean, val touchVisible: Boolean, val info: Boolean, val title: String,
                     val instantText: Boolean = false, val minimap: Boolean = false)

    /** Shiny odds: index into SHINY_LABELS (0 = the game's own). */
    data class Cheats(val shiny: Int, val noEncounters: Boolean, val noclip: Boolean)

    companion object {
        val SHINY_LABELS = listOf("game's odds", "1 in 512", "1 in 64", "1 in 8", "always")
    }

    private val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val items = ArrayList<Pair<Action, TextView>>()
    private var selected = 0
    private var cheatsPage = false
    private var scroll: ScrollView? = null
    private val dp = resources.displayMetrics.density

    init {
        setBackgroundColor(0xE6000000.toInt())   // the dark closes in
        isClickable = true
        setOnClickListener { onAction(Action.RESUME) }
        val panel = ScrollView(context).apply {
            background = GradientDrawable().apply { setColor(0xFF0D0D12.toInt()); cornerRadius = 24 * dp; setStroke((1 * dp).toInt(), 0xFF1E1E28.toInt()) }
            setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
            addView(list)
            isClickable = true
        }
        scroll = panel
        addView(panel, LayoutParams((300 * dp).toInt(), LayoutParams.WRAP_CONTENT, Gravity.CENTER))
    }

    fun show(s: State) {
        cheatsPage = false
        list.removeAllViews()
        items.clear()
        list.addView(TextView(context).apply {
            text = s.title.ifBlank { "Yami" }.uppercase()
            setTextColor(0xFF8C8B99.toInt()); textSize = 11f; letterSpacing = 0.16f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
        })
        add(Action.RESUME, "▶  Resume")
        add(Action.TURBO, if (s.turbo) "»  Speed-up: ON" else "»  Speed-up: off")
        add(Action.INSTANT_TEXT, if (s.instantText) "¶  Instant text: ON" else "¶  Instant text: off")
        add(Action.MINIMAP, if (s.minimap) "◫  Minimap: ON" else "◫  Minimap: off")
        add(Action.CHEATS, "✦  Cheats …")
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

    /** The cheats page; selection stays on [focus] after a change. */
    fun showCheats(c: Cheats, focus: Action? = null) {
        cheatsPage = true
        list.removeAllViews()
        items.clear()
        list.addView(TextView(context).apply {
            text = "CHEATS"
            setTextColor(0xFF8C8B99.toInt()); textSize = 11f; letterSpacing = 0.16f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
        })
        add(Action.CHEAT_SHINY, "✧  Shiny odds: ${SHINY_LABELS[c.shiny.coerceIn(0, SHINY_LABELS.size - 1)]}")
        add(Action.CHEAT_ENCOUNTERS, if (c.noEncounters) "⊘  No random encounters: ON" else "⊘  No random encounters: off")
        add(Action.CHEAT_NOCLIP, if (c.noclip) "⇢  Walk through walls: ON" else "⇢  Walk through walls: off")
        add(Action.CHEAT_MONEY, "$  Max money")
        add(Action.CHEAT_HEAL, "✚  Heal party")
        add(Action.BACK, "←  Back")
        list.addView(TextView(context).apply {
            text = "Shiny odds apply to Pokémon met from now on. Pokémon Essentials games; walking through walls and healing work in most RPG Maker games."
            setTextColor(0xFF4F4E5A.toInt()); textSize = 11f
            setPadding((14 * dp).toInt(), (8 * dp).toInt(), (14 * dp).toInt(), (6 * dp).toInt())
        })
        selected = items.indexOfFirst { it.first == focus }.coerceAtLeast(0)
        highlight()
        visibility = View.VISIBLE
    }

    private fun add(a: Action, label: String) {
        val tv = TextView(context).apply {
            text = label
            setTextColor(0xFFECEAF2.toInt()); textSize = 16f; typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            setPadding((14 * dp).toInt(), (12 * dp).toInt(), (14 * dp).toInt(), (12 * dp).toInt())
            setOnClickListener { onAction(a) }
        }
        items += a to tv
        list.addView(tv)
    }

    private fun highlight() {
        items.forEachIndexed { i, (_, tv) ->
            val on = i == selected
            tv.background = if (on) GradientDrawable().apply {
                setColor((accent and 0x00FFFFFF) or 0x24000000); cornerRadius = 14 * dp
                setStroke((1 * dp).toInt(), (accent and 0x00FFFFFF) or 0x66000000)
            } else null
            tv.setTextColor(if (on) accent else 0xFFECEAF2.toInt())
            if (on) scroll?.let { sv -> sv.post { sv.smoothScrollTo(0, (tv.top - tv.height).coerceAtLeast(0)) } }
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
            KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE ->
                onAction(if (cheatsPage) Action.BACK else Action.RESUME)
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
