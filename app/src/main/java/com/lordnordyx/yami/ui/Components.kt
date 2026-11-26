package com.lordnordyx.yami.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.lordnordyx.yami.ui.theme.Mono
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

// ------------------------------------------------------------------- covers
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
fun Cover(path: String?, title: String, modifier: Modifier = Modifier) {
    var bmp by remember(path) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(path) { bmp = path?.let { CoverCache.load(it) } }
    Box(modifier.background(Color(0xFF15151B))) {
        val b = bmp
        if (b != null) {
            // RPG Maker title art is pixel art: keep it crisp
            Image(b.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, filterQuality = FilterQuality.None)
        } else {
            Text(title.take(2).uppercase(), Modifier.align(Alignment.Center), fontFamily = Mono,
                style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.6f))
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.55f to Color.Transparent, 1f to Color(0xE6000000))))
    }
}

fun formatPlaytime(sec: Long): String = when {
    sec <= 0 -> "Not played"
    sec < 3600 -> "${sec / 60} min"
    else -> "%d h %02d m".format(sec / 3600, (sec % 3600) / 60)
}

// ----------------------------------------------------------- settings rows
@Composable
fun Section(title: String, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(title.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))
        Card(shape = RoundedCornerShape(18.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
            Column(Modifier.padding(vertical = 4.dp)) { content() }
        }
    }
}

@Composable
private fun RowShell(title: String, subtitle: String?, onClick: (() -> Unit)?, trailing: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (!subtitle.isNullOrBlank()) Text(subtitle, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.width(12.dp))
        trailing()
    }
}

@Composable
fun SwitchRow(title: String, checked: Boolean, subtitle: String? = null, onChange: (Boolean) -> Unit) =
    RowShell(title, subtitle, { onChange(!checked) }) { Switch(checked, onChange) }

@Composable
fun ActionRow(title: String, subtitle: String? = null, value: String? = null, onClick: () -> Unit = {}) =
    RowShell(title, subtitle, onClick) {
        if (value != null) Text(value, fontFamily = Mono, color = MaterialTheme.colorScheme.primary,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(140.dp))
    }

@Composable
fun <T> ChoiceRow(title: String, value: T, options: List<T>, label: (T) -> String, subtitle: String? = null, onChange: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        RowShell(title, subtitle, { open = true }) {
            Text(label(value), fontFamily = Mono, color = MaterialTheme.colorScheme.primary)
        }
        DropdownMenu(open, onDismissRequest = { open = false }, modifier = Modifier.align(Alignment.CenterEnd)) {
            options.forEach { o ->
                DropdownMenuItem(text = {
                    Text(label(o), fontWeight = if (o == value) FontWeight.Bold else FontWeight.Normal)
                }, onClick = { open = false; onChange(o) })
            }
        }
    }
}

@Composable
fun SliderRow(title: String, value: Float, range: ClosedFloatingPointRange<Float>, steps: Int = 0,
              format: (Float) -> String = { "%.2f".format(it) }, onChange: (Float) -> Unit) {
    var v by remember(value) { mutableStateOf(value) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Text(format(v), fontFamily = Mono, color = MaterialTheme.colorScheme.primary)
        }
        Slider(v, { v = it }, valueRange = range, steps = steps, onValueChangeFinished = { onChange(v) })
    }
}

// ------------------------------------------------------------- busy overlay
@Composable
fun BusyOverlay(busy: LibraryViewModel.Busy?, onCancel: () -> Unit) {
    busy ?: return
    Box(Modifier.fillMaxSize().background(Color(0xCC000000)).clickable(enabled = true) {}, contentAlignment = Alignment.Center) {
        Card(Modifier.padding(32.dp).fillMaxWidth(), shape = RoundedCornerShape(22.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh)) {
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(busy.title, style = MaterialTheme.typography.titleLarge)
                if (busy.detail.isNotBlank()) Text(busy.detail, fontFamily = Mono, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (busy.fraction >= 0f) LinearProgressIndicator(progress = { busy.fraction }, Modifier.fillMaxWidth().clip(RoundedCornerShape(4.dp)))
                else LinearProgressIndicator(Modifier.fillMaxWidth().clip(RoundedCornerShape(4.dp)))
                TextButton(onCancel, Modifier.align(Alignment.End)) { Text("Hide") }
            }
        }
    }
}
