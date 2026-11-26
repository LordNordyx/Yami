package com.lordnordyx.yami.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.lordnordyx.yami.ui.LibraryViewModel

val Mono = FontFamily.Monospace

@Composable
fun YamiTheme(vm: LibraryViewModel, content: @Composable () -> Unit) {
    val s by vm.settings.collectAsState()
    val accent = Color(s.accent)
    val bg = if (s.amoled) Color.Black else Color(0xFF0E0E12)
    val scheme = darkColorScheme(
        primary = accent,
        onPrimary = Color.White,
        secondary = Color(0xFF38E1C5),
        background = bg,
        surface = bg,
        surfaceVariant = Color(0xFF16161C),
        surfaceContainer = Color(0xFF111116),
        surfaceContainerHigh = Color(0xFF18181F),
        onBackground = Color(0xFFEDEDF2),
        onSurface = Color(0xFFEDEDF2),
        onSurfaceVariant = Color(0xFF9A9AA8),
        outline = Color(0xFF2A2A33),
    )
    val base = Typography()
    val type = base.copy(
        headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.Black, letterSpacing = (-1).sp),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold),
        labelSmall = TextStyle(fontFamily = Mono, fontSize = 11.sp, letterSpacing = 0.5.sp),
    )
    @Suppress("UNUSED_VARIABLE") val dark = isSystemInDarkTheme()
    MaterialTheme(colorScheme = scheme, typography = type, content = content)
}
