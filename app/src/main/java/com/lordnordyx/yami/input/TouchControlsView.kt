package com.lordnordyx.yami.input

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.Typeface
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.min

/**
 * On-screen controls drawn over the engine surface.
 *  - Floating analog: the stick appears under the thumb anywhere on the left half
 *  - Fixed stick / d-pad alternatives, 8-way with a deadzone
 *  - Buttons accept rolling the thumb from one to the next (C → B without lifting)
 *  - Edit mode ("free mode"): drag to move, double-tap to resize, long-press to hide
 */
@SuppressLint("ViewConstructor")
class TouchControlsView(
    context: Context,
    private val injector: KeyInjector,
    layout: TouchLayout,
    private val accent: Int,
) : View(context) {

    var layout: TouchLayout = layout
        set(v) { field = v; requestLayout(); invalidate() }
    var opacity = 0.55f
        set(v) { field = v; invalidate() }
    var haptics = true
    var editing = false
        set(v) { field = v; injector.releaseAll(); pointers.clear(); invalidate() }
    var onLayoutEdited: ((TouchLayout) -> Unit)? = null
    /** Turbo is a toggle in the engine; the overlay mirrors its real state. */
    var turboActive = false
        set(v) { if (field != v) { field = v; invalidate() } }

    private class Hit(val id: String, val cx: Float, val cy: Float, val r: Float, val el: TouchElement)
    private var hits = listOf<Hit>()

    private sealed interface Track
    private data class TrackButton(var id: String) : Track
    private data class TrackStick(val origin: PointF, val id: String, var dirs: Set<RgssButton> = emptySet(), val knob: PointF = PointF()) : Track
    private data class TrackEdit(val id: String, val dx: Float, val dy: Float, val downAt: Long) : Track
    private val pointers = HashMap<Int, Track>()
    private var lastTapId: String? = null
    private var lastTapAt = 0L

    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 3f; color = 0xFFFFFFFF.toInt() }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFFFFF.toInt(); textAlign = Paint.Align.CENTER; typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }
    private val dashed = Paint(stroke).apply { pathEffect = DashPathEffect(floatArrayOf(10f, 10f), 0f) }

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) = rebuild()

    private fun rebuild() {
        val s = min(width, height).toFloat()
        hits = layout.elements.filter { it.visible || editing }.map {
            Hit(it.id, it.cx * width, it.cy * height, it.size * s / 2f, it)
        }
    }

    // ------------------------------------------------------------------ input
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (editing) return onEditTouch(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                val used = down(e.getPointerId(i), e.getX(i), e.getY(i))
                // A first finger that misses every control goes to the game (mouse/touch scripts).
                if (!used && e.actionMasked == MotionEvent.ACTION_DOWN) return false
            }
            MotionEvent.ACTION_MOVE -> for (i in 0 until e.pointerCount) move(e.getPointerId(i), e.getX(i), e.getY(i))
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> up(e.getPointerId(e.actionIndex))
            MotionEvent.ACTION_CANCEL -> { pointers.keys.toList().forEach { up(it) } }
        }
        invalidate()
        return true
    }

    private fun hitAt(x: Float, y: Float, slop: Float = 1.15f): Hit? =
        hits.filter { it.el.visible }.minByOrNull { hypot(x - it.cx, y - it.cy) / it.r }
            ?.takeIf { hypot(x - it.cx, y - it.cy) <= it.r * slop }

    private fun stickHit() = hits.firstOrNull { it.el.kind != TouchKind.BUTTON && it.el.visible }

    /** @return true if the touch landed on a control. */
    private fun down(pid: Int, x: Float, y: Float): Boolean {
        val h = hitAt(x, y)
        if (h != null && h.el.kind == TouchKind.BUTTON) {
            pointers[pid] = TrackButton(h.id)
            injector.press(h.el.button)
            buzz()
            return true
        }
        val stick = stickHit() ?: return false
        val inStick = h?.id == stick.id
        if (inStick || (layout.floatingStick && stick.el.kind == TouchKind.STICK && x < width * 0.5f)) {
            val origin = if (layout.floatingStick && stick.el.kind == TouchKind.STICK) PointF(x, y) else PointF(stick.cx, stick.cy)
            val t = TrackStick(origin, stick.id)
            pointers[pid] = t
            updateStick(t, x, y, stick.r)
            return true
        }
        return false
    }

    private fun move(pid: Int, x: Float, y: Float) {
        when (val t = pointers[pid]) {
            is TrackButton -> {
                val h = hitAt(x, y, 1.0f)
                if (h != null && h.el.kind == TouchKind.BUTTON && h.id != t.id) {
                    hits.firstOrNull { it.id == t.id }?.let { injector.release(it.el.button) }
                    injector.press(h.el.button)
                    t.id = h.id
                    buzz()
                }
            }
            is TrackStick -> updateStick(t, x, y, hits.firstOrNull { it.id == t.id }?.r ?: 100f)
            else -> {}
        }
    }

    private fun up(pid: Int) {
        when (val t = pointers.remove(pid)) {
            is TrackButton -> hits.firstOrNull { it.id == t.id }?.let { injector.release(it.el.button) }
            is TrackStick -> t.dirs.forEach { injector.release(it) }
            else -> {}
        }
    }

    private fun updateStick(t: TrackStick, x: Float, y: Float, r: Float) {
        val dx = x - t.origin.x
        val dy = y - t.origin.y
        val dist = hypot(dx, dy)
        val clamp = if (dist > r) r / dist else 1f
        t.knob.set(t.origin.x + dx * clamp, t.origin.y + dy * clamp)
        val want: Set<RgssButton> = if (dist < r * 0.22f) emptySet() else {
            // 8 sectors of 45°, starting at "right"
            val sector = Math.floorMod(((Math.toDegrees(atan2(dy, dx).toDouble()) + 22.5) / 45.0).toInt(), 8)
            when (sector) {
                0 -> setOf(RgssButton.RIGHT)
                1 -> setOf(RgssButton.RIGHT, RgssButton.DOWN)
                2 -> setOf(RgssButton.DOWN)
                3 -> setOf(RgssButton.DOWN, RgssButton.LEFT)
                4 -> setOf(RgssButton.LEFT)
                5 -> setOf(RgssButton.LEFT, RgssButton.UP)
                6 -> setOf(RgssButton.UP)
                else -> setOf(RgssButton.UP, RgssButton.RIGHT)
            }
        }
        (t.dirs - want).forEach { injector.release(it) }
        (want - t.dirs).forEach { injector.press(it) }
        if (want != t.dirs && want.isNotEmpty()) buzz()
        t.dirs = want
    }

    private fun buzz() {
        if (haptics) performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    }

    // ------------------------------------------------------------- edit mode
    private fun onEditTouch(e: MotionEvent): Boolean {
        val i = e.actionIndex
        val pid = e.getPointerId(i)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val x = e.getX(i); val y = e.getY(i)
                val h = hits.minByOrNull { hypot(x - it.cx, y - it.cy) / it.r }
                    ?.takeIf { hypot(x - it.cx, y - it.cy) <= it.r * 1.3f } ?: return true
                val now = e.eventTime
                if (lastTapId == h.id && now - lastTapAt < 300) {
                    // double tap: cycle size
                    edit(h.id) { val next = if (it.size >= 0.42f) 0.08f else it.size * 1.2f; it.copy(size = next) }
                    lastTapId = null
                } else {
                    lastTapId = h.id; lastTapAt = now
                }
                pointers[pid] = TrackEdit(h.id, x - h.cx, y - h.cy, now)
            }
            MotionEvent.ACTION_MOVE -> for (k in 0 until e.pointerCount) {
                val t = pointers[e.getPointerId(k)] as? TrackEdit ?: continue
                val nx = ((e.getX(k) - t.dx) / width).coerceIn(0.03f, 0.97f)
                val ny = ((e.getY(k) - t.dy) / height).coerceIn(0.03f, 0.97f)
                edit(t.id) { it.copy(cx = nx, cy = ny) }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val t = pointers.remove(pid) as? TrackEdit
                if (t != null && e.eventTime - t.downAt > 650) {
                    val h = hits.firstOrNull { it.id == t.id }
                    if (h != null && hypot(e.getX(i) - t.dx - h.cx, e.getY(i) - t.dy - h.cy) < 12f) {
                        edit(t.id) { it.copy(visible = !it.visible) } // long-press: hide/show
                    }
                }
                onLayoutEdited?.invoke(layout)
            }
        }
        return true
    }

    private fun edit(id: String, f: (TouchElement) -> TouchElement) {
        layout = layout.copy(elements = layout.elements.map { if (it.id == id) f(it) else it })
        rebuild()
        invalidate()
    }

    fun resetLayout() {
        layout = layout.copy(elements = TouchLayout.defaultElements())
        rebuild()
        onLayoutEdited?.invoke(layout)
    }

    // ---------------------------------------------------------------- drawing
    override fun onDraw(c: Canvas) {
        if (hits.size != layout.elements.count { it.visible || editing }) rebuild()
        val a = (opacity * 255).toInt().coerceIn(0, 255)
        stroke.alpha = a
        text.alpha = a
        val pressedIds = pointers.values.mapNotNull { (it as? TrackButton)?.id }.toSet()
        for (h in hits) {
            val p = if (h.el.visible) stroke else dashed.also { it.alpha = a / 2 }
            when (h.el.kind) {
                TouchKind.BUTTON -> {
                    if (h.id in pressedIds || (h.el.button == RgssButton.TURBO && turboActive)) {
                        fill.color = accent; fill.alpha = (a * 0.8f).toInt()
                        c.drawCircle(h.cx, h.cy, h.r, fill)
                    } else {
                        fill.color = 0xFF000000.toInt(); fill.alpha = a / 3
                        c.drawCircle(h.cx, h.cy, h.r, fill)
                    }
                    c.drawCircle(h.cx, h.cy, h.r, p)
                    text.textSize = h.r * 0.8f
                    c.drawText(h.el.label, h.cx, h.cy + text.textSize * 0.35f, text)
                }
                TouchKind.STICK, TouchKind.DPAD -> {
                    val track = pointers.values.firstOrNull { it is TrackStick && it.id == h.id } as? TrackStick
                    if (track == null && layout.floatingStick && h.el.kind == TouchKind.STICK && !editing) {
                        // idle floating stick: faint hint where it usually sits
                        dashed.alpha = a / 3
                        c.drawCircle(h.cx, h.cy, h.r, dashed)
                        continue
                    }
                    val ox = track?.origin?.x ?: h.cx
                    val oy = track?.origin?.y ?: h.cy
                    fill.color = 0xFF000000.toInt(); fill.alpha = a / 3
                    c.drawCircle(ox, oy, h.r, fill)
                    c.drawCircle(ox, oy, h.r, p)
                    if (h.el.kind == TouchKind.DPAD) {
                        c.drawLine(ox - h.r * 0.7f, oy, ox + h.r * 0.7f, oy, p)
                        c.drawLine(ox, oy - h.r * 0.7f, ox, oy + h.r * 0.7f, p)
                    }
                    val kx = track?.knob?.x ?: ox
                    val ky = track?.knob?.y ?: oy
                    fill.color = accent; fill.alpha = a
                    c.drawCircle(kx, ky, h.r * 0.38f, fill)
                }
            }
        }
        if (editing) {
            text.textSize = 28f; text.alpha = 255
            c.drawText("Drag to move · double-tap to resize · hold to hide/show", width / 2f, height * 0.5f, text)
        }
    }
}
