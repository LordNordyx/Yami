package com.lordnordyx.yami.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * Behind every screen: black, a slow aurora of the accent colour low on the
 * horizon, and a scatter of pixel-square stars that breathe.
 */
@Composable
fun DarkBackdrop(modifier: Modifier = Modifier) {
    val accent = MaterialTheme.colorScheme.primary
    val t = rememberInfiniteTransition(label = "backdrop")
    val phase by t.animateFloat(0f, (2 * Math.PI).toFloat(),
        infiniteRepeatable(tween(28_000, easing = LinearEasing), RepeatMode.Restart), label = "phase")
    val stars = remember {
        val r = Random(7)
        List(70) { floatArrayOf(r.nextFloat(), r.nextFloat(), r.nextFloat() * 6.28f, if (r.nextFloat() < 0.15f) 2f else 1f) }
    }
    Canvas(modifier.fillMaxSize()) {
        drawRect(Color.Black)
        val w = size.width; val h = size.height
        val big = maxOf(w, h)
        // two soft blooms drifting against each other
        val a = Offset(w * (0.25f + 0.10f * sin(phase)), h * (1.02f + 0.04f * cos(phase)))
        val b = Offset(w * (0.80f + 0.08f * cos(phase * 1f + 1.3f)), h * (0.98f + 0.05f * sin(phase + 0.7f)))
        drawCircle(Brush.radialGradient(listOf(accent.copy(alpha = 0.16f), Color.Transparent), a, big * 0.55f), big * 0.55f, a)
        drawCircle(Brush.radialGradient(listOf(accent.copy(alpha = 0.10f), Color.Transparent), b, big * 0.45f), big * 0.45f, b)
        // a faint eclipse glow at the top
        val c = Offset(w * 0.5f, -big * 0.25f)
        drawCircle(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.035f), Color.Transparent), c, big * 0.6f), big * 0.6f, c)
        // pixel stars
        val px = 1.6f * density
        for (s in stars) {
            val alpha = 0.10f + 0.22f * (0.5f + 0.5f * sin(phase * 3 + s[2]))
            val sz = px * s[3]
            drawRect(Color.White.copy(alpha = alpha), Offset(s[0] * w, s[1] * h * 0.85f), Size(sz, sz))
        }
    }
}
