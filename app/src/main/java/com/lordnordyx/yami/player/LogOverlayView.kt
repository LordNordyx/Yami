package com.lordnordyx.yami.player

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import kotlin.concurrent.thread

/** Full-screen log viewer inside the game, for black screens and hangs. */
@SuppressLint("ViewConstructor", "SetTextI18n")
class LogOverlayView(context: Context, private val accent: Int, private val onClose: () -> Unit) : FrameLayout(context) {

    private val text = TextView(context).apply {
        setTextColor(0xFFE6E6E6.toInt()); textSize = 10f; typeface = Typeface.MONOSPACE
        setTextIsSelectable(true)
    }
    private val scroll = ScrollView(context)
    private var content = ""

    init {
        setBackgroundColor(0xF2000000.toInt())
        isClickable = true
        val dp = resources.displayMetrics.density
        val bar = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.END }
        fun btn(label: String, f: () -> Unit) = TextView(context).apply {
            text = label; setTextColor(accent); textSize = 15f; typeface = Typeface.MONOSPACE
            setPadding((14 * dp).toInt(), (12 * dp).toInt(), (14 * dp).toInt(), (12 * dp).toInt())
            setOnClickListener { f() }
        }
        bar.addView(btn("Refresh") { refresh() })
        bar.addView(btn("Copy") {
            (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                .setPrimaryClip(ClipData.newPlainText("Yami log", content))
            Toast.makeText(context, "Log copied", Toast.LENGTH_SHORT).show()
        })
        bar.addView(btn("Share") {
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"; putExtra(Intent.EXTRA_SUBJECT, "Yami log"); putExtra(Intent.EXTRA_TEXT, content)
            }, "Share log").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        })
        bar.addView(btn("Close") { onClose() })
        val col = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        col.addView(bar)
        scroll.addView(HorizontalScrollView(context).apply { addView(text) })
        col.addView(scroll, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(col, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        setPadding((12 * dp).toInt(), (12 * dp).toInt(), (12 * dp).toInt(), (12 * dp).toInt())
    }

    fun refresh() {
        text.text = "Loading log…"
        thread {
            val log = CrashReports.sessionLog(context)
            post {
                content = log
                text.text = log
                scroll.post { scroll.fullScroll(ScrollView.FOCUS_DOWN) }
            }
        }
    }
}
