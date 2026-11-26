package com.lordnordyx.yami.player

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.BatteryManager
import android.view.View
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Compact HUD: engine FPS, clock, battery, turbo badge. */
class InfoOverlayView(context: Context, private val accent: Int) : View(context) {

    var fps = 0
    var turbo = false
    var showInfo = true
    private val clock = SimpleDateFormat("HH:mm", Locale.getDefault())
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFFFFF.toInt(); textSize = 30f; typeface = Typeface.MONOSPACE
    }
    private val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x99000000.toInt() }
    private val badge = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = accent }

    init { isClickable = false; isFocusable = false }

    private fun battery(): Int {
        val i: Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = i?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = i?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        return if (level < 0) -1 else level * 100 / scale
    }

    fun refresh() = postInvalidate()

    override fun onDraw(c: Canvas) {
        val pad = 14f
        var x = pad + 24f
        val y = pad + 34f
        if (showInfo) {
            val b = battery()
            val line = "${fps.toString().padStart(2)} FPS  ${clock.format(Date())}  ${if (b >= 0) "$b%" else ""}"
            val w = paint.measureText(line)
            c.drawRoundRect(RectF(pad, pad, pad + w + 48f, pad + 48f), 14f, 14f, bg)
            c.drawText(line, x, y, paint)
            x += w + 48f
        }
        if (turbo) {
            val label = "» TURBO"
            val w = paint.measureText(label)
            c.drawRoundRect(RectF(x, pad, x + w + 32f, pad + 48f), 14f, 14f, badge)
            c.drawText(label, x + 16f, y, paint)
        }
    }
}
