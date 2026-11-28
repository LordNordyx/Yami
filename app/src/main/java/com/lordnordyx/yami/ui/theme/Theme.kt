package com.lordnordyx.yami.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.lordnordyx.yami.R
import com.lordnordyx.yami.ui.LibraryViewModel

/*
 * Yami — the god of darkness. Pure black, surfaces barely lifted off it,
 * hairlines instead of shadows, one accent of light.
 */
object Dark {
    val Void = Color(0xFF000000)       // background: AMOLED black
    val Abyss = Color(0xFF07070A)      // faintest lift (bars, sheets)
    val Shade = Color(0xFF0D0D12)      // cards
    val Dusk = Color(0xFF15151C)       // pressed / raised
    val Hairline = Color(0xFF1E1E28)   // borders, dividers
    val Ink = Color(0xFFECEAF2)        // primary text
    val Mist = Color(0xFF8C8B99)       // secondary text
    val Faint = Color(0xFF4F4E5A)      // tertiary text, inactive controls
    val Danger = Color(0xFFFF4D5E)
}

/** Accents, named for the dark. The first is the default. */
data class Accent(val name: String, val argb: Long)

val ACCENTS = listOf(
    Accent("Eclipse", 0xFF8B6CFF),
    Accent("Blood Moon", 0xFFE5394F),
    Accent("Abyss", 0xFF2BD9C2),
    Accent("Ember", 0xFFFF7A3D),
    Accent("Moonlight", 0xFFB8C4FF),
    Accent("Ash", 0xFFE8E8EC),
)

/** Kept for code that shows paths or numbers in a fixed-width face. */
val Mono = FontFamily.Monospace
private val Sans = FontFamily.SansSerif

/** Pixel faces (both OFL): Silkscreen for tiny caps labels, Pixelify Sans for titles. */
val PixelCaps = FontFamily(Font(R.font.silkscreen))
val PixelTitle = FontFamily(Font(R.font.pixelify_sans))

/** Frosted glass on black: a whisper of white, brighter at the top edge. */
object Glass {
    val Fill = Color(0x0DFFFFFF)
    val FillStrong = Color(0x17FFFFFF)
    val EdgeTop = Color(0x33FFFFFF)
    val EdgeBottom = Color(0x0AFFFFFF)
}

@Composable
fun YamiTheme(vm: LibraryViewModel, content: @Composable () -> Unit) {
    val s by vm.settings.collectAsState()
    val accent = Color(s.accent)
    val scheme = darkColorScheme(
        primary = accent,
        onPrimary = Dark.Void,
        primaryContainer = accent.copy(alpha = 0.16f),
        onPrimaryContainer = accent,
        secondary = accent,
        onSecondary = Dark.Void,
        secondaryContainer = Dark.Dusk,
        onSecondaryContainer = Dark.Ink,
        tertiary = accent,
        background = Dark.Void,
        onBackground = Dark.Ink,
        surface = Dark.Void,
        onSurface = Dark.Ink,
        surfaceVariant = Dark.Shade,
        onSurfaceVariant = Dark.Mist,
        surfaceContainerLowest = Dark.Void,
        surfaceContainerLow = Dark.Abyss,
        surfaceContainer = Dark.Shade,
        surfaceContainerHigh = Dark.Dusk,
        surfaceContainerHighest = Dark.Dusk,
        surfaceBright = Dark.Dusk,
        surfaceDim = Dark.Void,
        inverseSurface = Dark.Ink,
        inverseOnSurface = Dark.Void,
        outline = Dark.Hairline,
        outlineVariant = Dark.Hairline,
        error = Dark.Danger,
        onError = Dark.Void,
        scrim = Color(0xE6000000),
    )
    val base = Typography()
    fun TextStyle.sans() = copy(fontFamily = Sans)
    val type = Typography(
        displayLarge = base.displayLarge.sans(),
        displayMedium = base.displayMedium.sans(),
        displaySmall = base.displaySmall.sans(),
        headlineLarge = base.headlineLarge.sans().copy(fontWeight = FontWeight.Light, letterSpacing = 0.sp),
        headlineMedium = base.headlineMedium.sans().copy(fontWeight = FontWeight.Light),
        headlineSmall = base.headlineSmall.copy(fontFamily = PixelTitle, fontWeight = FontWeight.Normal),
        titleLarge = base.titleLarge.copy(fontFamily = PixelTitle, fontWeight = FontWeight.Normal),
        titleMedium = base.titleMedium.sans().copy(fontWeight = FontWeight.Medium),
        titleSmall = base.titleSmall.sans().copy(fontWeight = FontWeight.Medium),
        bodyLarge = base.bodyLarge.sans().copy(fontSize = 16.sp, letterSpacing = 0.1.sp),
        bodyMedium = base.bodyMedium.sans(),
        bodySmall = base.bodySmall.sans().copy(lineHeight = 17.sp),
        labelLarge = base.labelLarge.sans().copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.4.sp),
        labelMedium = base.labelMedium.sans(),
        // section labels: small, wide-tracked capitals
        labelSmall = TextStyle(fontFamily = PixelCaps, fontSize = 10.sp, fontWeight = FontWeight.Normal, letterSpacing = 1.2.sp),
    )
    MaterialTheme(colorScheme = scheme, typography = type, content = content)
}
