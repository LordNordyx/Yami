package com.lordnordyx.yami.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lordnordyx.yami.ui.theme.Dark
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

// ================================================================ focus
/**
 * A clear accent outline on whatever a controller (or keyboard) has
 * selected; Material's focus tint is nearly invisible on black. Put it
 * before clickable/focusable in the chain.
 */
fun Modifier.focusRing(shape: Shape = RoundedCornerShape(16.dp), width: Dp = 2.dp): Modifier = composed {
    var focused by remember { mutableStateOf(false) }
    val accent = MaterialTheme.colorScheme.primary
    this.onFocusChanged { focused = it.isFocused }
        .then(if (focused) Modifier.border(width, accent, shape).background(accent.copy(alpha = 0.10f), shape) else Modifier)
}

// ================================================================ the mark
/**
 * Yami's mark: an eclipse. A black moon over a thin corona of light, with a
 * single bead where the light breaks through ("diamond ring").
 */
@Composable
fun EclipseMark(modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.primary, glow: Boolean = true) {
    Canvas(modifier) {
        val r = size.minDimension / 2f
        val c = Offset(size.width / 2f, size.height / 2f)
        if (glow) drawCircle(Brush.radialGradient(listOf(color.copy(alpha = 0.28f), Color.Transparent), c, r), r, c)
        val ring = r * 0.70f
        val moon = r * 0.58f
        val shift = r * 0.083f
        val path = Path().apply {
            fillType = PathFillType.EvenOdd
            addOval(androidx.compose.ui.geometry.Rect(c, ring))
            addOval(androidx.compose.ui.geometry.Rect(Offset(c.x + shift, c.y - shift), moon))
        }
        drawCircle(Color.Black, moon, Offset(c.x + shift, c.y - shift))   // the moon is pitch black
        drawPath(path, color)
        // the bead, at the ring's thinnest point
        val d = 0.7071f * ring
        drawCircle(Color.White, r * 0.07f, Offset(c.x + d, c.y - d))
    }
}

/** YAMI, set wide and light. */
@Composable
fun Wordmark(size: Int = 22) {
    Text("YAMI", fontSize = size.sp, fontFamily = com.lordnordyx.yami.ui.theme.PixelCaps, letterSpacing = (size * 0.22f).sp,
        color = MaterialTheme.colorScheme.onBackground)
}

/** Frosted glass: a faint white wash with light catching the top edge. */
fun Modifier.glass(shape: androidx.compose.ui.graphics.Shape, strong: Boolean = false): Modifier = this
    .clip(shape)
    .background(if (strong) com.lordnordyx.yami.ui.theme.Glass.FillStrong else com.lordnordyx.yami.ui.theme.Glass.Fill)
    .border(1.dp, androidx.compose.ui.graphics.Brush.verticalGradient(
        listOf(com.lordnordyx.yami.ui.theme.Glass.EdgeTop, com.lordnordyx.yami.ui.theme.Glass.EdgeBottom)), shape)

// ================================================================ covers
object CoverCache {
    private val cache = object : LruCache<String, Bitmap>(48 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    suspend fun load(path: String, maxW: Int = 720): Bitmap? = withContext(Dispatchers.IO) {
        cache.get(path)?.let { return@withContext it }
        val f = File(path)
        if (!f.exists()) return@withContext null
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, opts)
        var sample = 1
        while (opts.outWidth / (sample * 2) >= maxW) sample *= 2
        val bmp = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return@withContext null
        cache.put(path, bmp)
        bmp
    }
}

@Composable
fun Cover(path: String?, title: String, modifier: Modifier = Modifier, fade: Boolean = true) {
    var bmp by remember(path) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(path) { bmp = path?.let { CoverCache.load(it) } }
    Box(modifier.background(Dark.Shade)) {
        val b = bmp
        if (b != null) {
            // RPG Maker title art is pixel art: keep it crisp
            Image(b.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, filterQuality = FilterQuality.None)
        } else {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                EclipseMark(Modifier.size(44.dp), MaterialTheme.colorScheme.primary.copy(alpha = 0.55f))
                Spacer(Modifier.height(6.dp))
                Text(title.take(18), style = MaterialTheme.typography.labelSmall, color = Dark.Faint, maxLines = 1)
            }
        }
        if (fade) Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.45f to Color.Transparent, 1f to Color(0xF2000000))))
    }
}

fun formatPlaytime(sec: Long): String = when {
    sec <= 0 -> "Not played"
    sec < 3600 -> "${sec / 60} min"
    else -> "%d h %02d m".format(sec / 3600, (sec % 3600) / 60)
}

// ================================================================ screens
/** Top bar: back arrow, title, actions. Sits under the status bar. */
@Composable
fun YamiTopBar(title: String, onBack: (() -> Unit)?, actions: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 4.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) IconButton(onBack, Modifier.focusRing(CircleShape)) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        else Spacer(Modifier.width(12.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f),
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        actions()
    }
}

/** A scrolling settings-style page with a top bar. */
@Composable
fun YamiPage(title: String, onBack: (() -> Unit)?, actions: @Composable RowScope.() -> Unit = {},
             content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize()) {
        YamiTopBar(title, onBack, actions)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding()) {
            content()
            Spacer(Modifier.height(40.dp))
        }
    }
}

// ================================================================ sections & rows
@Composable
fun Section(title: String?, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        if (!title.isNullOrBlank()) Text(title.uppercase(), style = MaterialTheme.typography.labelSmall,
            color = Dark.Mist, modifier = Modifier.padding(start = 6.dp, bottom = 8.dp))
        Column(Modifier.fillMaxWidth().glass(RoundedCornerShape(20.dp)).padding(vertical = 4.dp)) { content() }
    }
}

/** Explanatory text inside a section. */
@Composable
fun SectionNote(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = Dark.Mist,
        modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp))
}

@Composable
fun RowDivider() = HorizontalDivider(Modifier.padding(start = 18.dp), thickness = 1.dp, color = Dark.Hairline)

@Composable
private fun RowShell(title: String, subtitle: String?, icon: ImageVector?, onClick: (() -> Unit)?,
                     enabled: Boolean = true, trailing: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp)
            .then(if (onClick != null && enabled) Modifier.focusRing(RoundedCornerShape(14.dp)).clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Box(Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(Dark.Dusk), contentAlignment = Alignment.Center) {
                Icon(icon, null, Modifier.size(18.dp), tint = if (enabled) MaterialTheme.colorScheme.primary else Dark.Faint)
            }
            Spacer(Modifier.width(14.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = if (enabled) Dark.Ink else Dark.Faint)
            if (!subtitle.isNullOrBlank()) Text(subtitle, style = MaterialTheme.typography.bodySmall,
                color = if (enabled) Dark.Mist else Dark.Faint, modifier = Modifier.padding(top = 2.dp))
        }
        Spacer(Modifier.width(12.dp))
        trailing()
    }
}

/** Opens a sub-menu. */
@Composable
fun NavRow(title: String, subtitle: String? = null, icon: ImageVector? = null, value: String? = null, onClick: () -> Unit) =
    RowShell(title, subtitle, icon, onClick) {
        if (value != null) Text(value, style = MaterialTheme.typography.bodyMedium, color = Dark.Mist, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 140.dp))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Dark.Faint)
    }

@Composable
fun yamiSwitchColors() = SwitchDefaults.colors(
    checkedThumbColor = Dark.Void,
    checkedTrackColor = MaterialTheme.colorScheme.primary,
    checkedBorderColor = MaterialTheme.colorScheme.primary,
    uncheckedThumbColor = Dark.Faint,
    uncheckedTrackColor = Dark.Void,
    uncheckedBorderColor = Dark.Hairline,
)

@Composable
fun SwitchRow(title: String, checked: Boolean, subtitle: String? = null, icon: ImageVector? = null, onChange: (Boolean) -> Unit) =
    RowShell(title, subtitle, icon, { onChange(!checked) }) { Switch(checked, onChange, colors = yamiSwitchColors()) }

@Composable
fun ActionRow(title: String, subtitle: String? = null, value: String? = null, icon: ImageVector? = null,
              danger: Boolean = false, onClick: (() -> Unit)? = null) =
    RowShell(title, subtitle, icon, onClick) {
        if (value != null) Text(value, style = MaterialTheme.typography.bodyMedium,
            color = if (danger) Dark.Danger else MaterialTheme.colorScheme.primary,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 160.dp))
    }

/** A choice: shows the current value; tapping opens a sheet with every option explained. */
@Composable
fun <T> ChoiceRow(title: String, value: T, options: List<T>, label: (T) -> String, subtitle: String? = null,
                  describe: ((T) -> String?)? = null, icon: ImageVector? = null, onChange: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    RowShell(title, subtitle, icon, { open = true }) {
        Text(label(value), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 150.dp))
    }
    if (open) OptionSheet(title, options, value, label, describe, onDismiss = { open = false }) { open = false; onChange(it) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> OptionSheet(title: String, options: List<T>, selected: T?, label: (T) -> String, describe: ((T) -> String?)?,
                    onDismiss: () -> Unit, onPick: (T) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Dark.Abyss, scrimColor = Color(0xCC000000), dragHandle = { SheetHandle() }) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 16.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            options.forEach { o ->
                val sel = o == selected
                Row(Modifier.fillMaxWidth().focusRing(RoundedCornerShape(14.dp)).clickable { onPick(o) }.padding(horizontal = 24.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(label(o), style = MaterialTheme.typography.bodyLarge,
                            color = if (sel) MaterialTheme.colorScheme.primary else Dark.Ink,
                            fontWeight = if (sel) FontWeight.SemiBold else FontWeight.Normal)
                        describe?.invoke(o)?.takeIf { it.isNotBlank() }?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall, color = Dark.Mist, modifier = Modifier.padding(top = 2.dp))
                        }
                    }
                    if (sel) Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

@Composable
fun SheetHandle() {
    Box(Modifier.padding(vertical = 12.dp).size(width = 36.dp, height = 4.dp).clip(CircleShape).background(Dark.Hairline))
}

@Composable
fun SliderRow(title: String, value: Float, range: ClosedFloatingPointRange<Float>, steps: Int = 0,
              format: (Float) -> String = { "%.2f".format(it) }, subtitle: String? = null, onChange: (Float) -> Unit) {
    var v by remember(value) { mutableStateOf(value) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                if (!subtitle.isNullOrBlank()) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Dark.Mist)
            }
            Text(format(v), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold)
        }
        Slider(v, { v = it }, valueRange = range, steps = steps, onValueChangeFinished = { onChange(v) },
            colors = SliderDefaults.colors(
                thumbColor = MaterialTheme.colorScheme.primary,
                activeTrackColor = MaterialTheme.colorScheme.primary,
                inactiveTrackColor = Dark.Hairline,
                activeTickColor = Dark.Void,
                inactiveTickColor = Dark.Faint,
            ))
    }
}

// ================================================================ buttons
@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null, height: Dp = 52.dp) {
    Button(onClick, modifier.focusRing(CircleShape, 3.dp).height(height), shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary, contentColor = Dark.Void),
        contentPadding = PaddingValues(horizontal = 22.dp)) {
        if (icon != null) { Icon(icon, null, Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, style = MaterialTheme.typography.labelLarge, fontSize = 15.sp)
    }
}

@Composable
fun GhostButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null, height: Dp = 52.dp) {
    OutlinedButton(onClick, modifier.focusRing(CircleShape).height(height), shape = CircleShape, border = BorderStroke(1.dp, Dark.Hairline),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = Dark.Ink),
        contentPadding = PaddingValues(horizontal = 20.dp)) {
        if (icon != null) { Icon(icon, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, style = MaterialTheme.typography.labelLarge)
    }
}

// ================================================================ busy overlay
@Composable
fun BusyOverlay(busy: LibraryViewModel.Busy?, onCancel: () -> Unit) {
    busy ?: return
    Box(Modifier.fillMaxSize().background(Color(0xE6000000)).clickable(enabled = true) {}, contentAlignment = Alignment.Center) {
        Column(Modifier.padding(32.dp).fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Dark.Shade)
            .border(1.dp, Dark.Hairline, RoundedCornerShape(24.dp)).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                EclipseMark(Modifier.size(28.dp))
                Spacer(Modifier.width(12.dp))
                Text(busy.title, style = MaterialTheme.typography.titleMedium)
            }
            if (busy.detail.isNotBlank()) Text(busy.detail, maxLines = 1, overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodySmall, color = Dark.Mist)
            val bar = Modifier.fillMaxWidth().height(3.dp).clip(CircleShape)
            if (busy.fraction >= 0f) LinearProgressIndicator(progress = { busy.fraction }, bar,
                color = MaterialTheme.colorScheme.primary, trackColor = Dark.Hairline)
            else LinearProgressIndicator(bar, color = MaterialTheme.colorScheme.primary, trackColor = Dark.Hairline)
            TextButton(onCancel, Modifier.align(Alignment.End)) { Text("Hide", color = Dark.Mist) }
        }
    }
}
