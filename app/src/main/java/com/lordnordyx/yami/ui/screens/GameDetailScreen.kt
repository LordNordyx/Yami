package com.lordnordyx.yami.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.outlined.AutoFixHigh
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.DriveFileRenameOutline
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.lordnordyx.yami.ui.ActionRow
import com.lordnordyx.yami.ui.BusyOverlay
import com.lordnordyx.yami.ui.Cover
import com.lordnordyx.yami.ui.GhostButton
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.NavRow
import com.lordnordyx.yami.ui.PrimaryButton
import com.lordnordyx.yami.ui.Section
import com.lordnordyx.yami.ui.formatPlaytime
import com.lordnordyx.yami.ui.theme.Dark
import com.lordnordyx.yami.ui.theme.Mono
import java.text.DateFormat
import java.util.Date

@Composable
fun GameDetailScreen(vm: LibraryViewModel, id: String, back: () -> Unit, openSettings: () -> Unit) {
    val ctx = LocalContext.current
    val games by vm.repo.games.collectAsState()
    val busy by vm.busy.collectAsState()
    val g = games.firstOrNull { it.id == id } ?: run { Text("Game not found", Modifier.statusBarsPadding().padding(24.dp)); return }
    var renaming by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    var showSaves by remember { mutableStateOf(false) }
    var refresh by remember { mutableIntStateOf(0) }

    val exportSaves = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        uri?.let { vm.saves.export(g, it); vm.message.value = "Saves exported" }
    }
    val importSaves = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { vm.saves.import(g, it); refresh++; vm.message.value = "Saves imported" }
    }

    Box(Modifier.fillMaxSize().background(Dark.Void)) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding()) {
            Box(Modifier.fillMaxWidth().height(320.dp)) {
                Cover(g.coverPath, g.title, Modifier.fillMaxSize())
                Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 8.dp, vertical = 6.dp)) {
                    RoundIcon({ Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }, back)
                    Spacer(Modifier.weight(1f))
                    RoundIcon({
                        Icon(if (g.favorite) Icons.Default.Star else Icons.Default.StarBorder, "Favorite",
                            tint = if (g.favorite) MaterialTheme.colorScheme.primary else Dark.Ink)
                    }) { vm.toggleFavorite(id) }
                }
                Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp, vertical = 16.dp)) {
                    Text(g.engineHint.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.height(4.dp))
                    Text(g.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Normal, color = Dark.Ink,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                PrimaryButton("Play", { vm.play(ctx, id) }, Modifier.weight(1f), icon = Icons.Default.PlayArrow, height = 56.dp)
                GhostButton(if (g.optimize == null) "Optimize" else "Re-optimize", { vm.optimize(id, thenPlay = false, ctx = ctx) },
                    icon = Icons.Outlined.AutoFixHigh, height = 56.dp)
            }
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile("Played", formatPlaytime(g.playTimeSec), Modifier.weight(1f))
                StatTile("Last", if (g.lastPlayed > 0) DateFormat.getDateInstance(DateFormat.SHORT).format(Date(g.lastPlayed)) else "—", Modifier.weight(1f))
                StatTile("Launches", g.launches.toString(), Modifier.weight(1f))
                StatTile("Engine", "RGSS${g.rgssVersion}", Modifier.weight(1f))
            }

            Section("Game") {
                NavRow("Settings", if (g.useGlobalSettings) "Following the game defaults" else "Tuned for this game",
                    Icons.Outlined.Tune) { openSettings() }
            }

            g.optimize?.let { o ->
                Section("Optimization") {
                    ActionRow("Status", o.note.ifBlank { "Ready" })
                    ActionRow("Resource index", value = "${o.indexedFiles} files")
                    ActionRow("Maps", value = "${o.maps} · ${o.mapBytes / 1024} KiB")
                    if (o.optimizedTilesets > 0) ActionRow("Compact tilesets", value = "${o.mapVariants} from ${o.optimizedTilesets}")
                    if (o.savedPixels > 0) ActionRow("Texture memory saved", value = "${o.savedPixels * 4 / (1024 * 1024)} MB")
                    if (o.archiveExtracted) ActionRow("Restore original archive", "Removes unpacked files, puts Game.rgssad back") { vm.restoreArchive(id) }
                    ActionRow("Delete optimized maps", value = "Delete", danger = true) { vm.deleteOptimized(id) }
                }
            }

            Section("Saves") {
                NavRow("Manage saves", "A snapshot is taken before every launch", Icons.Outlined.History,
                    value = "${vm.saves.list(g).size}") { showSaves = true }
                ActionRow("Export saves", "As a .zip", icon = Icons.Outlined.FileUpload) { exportSaves.launch("${g.title} saves.zip") }
                ActionRow("Import saves", "From a .zip", icon = Icons.Outlined.FileDownload) { importSaves.launch(arrayOf("application/zip", "application/octet-stream")) }
            }

            Section("Library") {
                ActionRow("Rename", icon = Icons.Outlined.DriveFileRenameOutline) { renaming = true }
                ActionRow("Location", g.path, icon = Icons.Outlined.Folder)
                ActionRow("Remove from library", icon = Icons.Outlined.DeleteOutline, value = "Remove", danger = true) { confirmRemove = true }
            }
            Spacer(Modifier.height(40.dp))
        }
        BusyOverlay(busy, vm::cancel)
    }

    if (renaming) {
        var t by remember { mutableStateOf(g.title) }
        DarkDialog("Rename", onDismiss = { renaming = false },
            confirm = "Save" to { vm.rename(id, t); renaming = false },
            dismiss = "Cancel" to { renaming = false }) {
            OutlinedTextField(t, { t = it }, singleLine = true, shape = RoundedCornerShape(14.dp),
                colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = Dark.Hairline, cursorColor = MaterialTheme.colorScheme.primary))
        }
    }
    if (confirmRemove) {
        DarkDialog("Remove ${g.title}?", onDismiss = { confirmRemove = false },
            confirm = "Remove" to { vm.remove(id, deleteFiles = true); confirmRemove = false; back() },
            dismiss = "Keep files" to { vm.remove(id, deleteFiles = false); confirmRemove = false; back() }) {
            Text(if (g.inPlace) "The game folder stays where it is. Yami's saves for it are deleted."
                 else "Deletes the imported copy and Yami's saves for it. Export saves first if you want to keep them.",
                style = MaterialTheme.typography.bodyMedium, color = Dark.Mist)
        }
    }
    if (showSaves) {
        val snaps = remember(refresh) { vm.saves.snapshots(g) }
        val files = remember(refresh) { vm.saves.list(g) }
        DarkDialog("Saves", onDismiss = { showSaves = false }, confirm = "Close" to { showSaves = false }) {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                if (files.isEmpty()) Text("No saves yet", color = Dark.Mist)
                files.forEach {
                    Text("${it.file.name}  ·  ${it.location}", fontFamily = Mono, style = MaterialTheme.typography.bodySmall, color = Dark.Ink,
                        modifier = Modifier.padding(vertical = 3.dp))
                }
                if (snaps.isNotEmpty()) {
                    Spacer(Modifier.height(14.dp))
                    Text("SNAPSHOTS — TAP TO RESTORE", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    snaps.forEach { z ->
                        TextButton({ vm.saves.restore(g, z); refresh++; vm.message.value = "Restored ${z.nameWithoutExtension}" }) {
                            Text(z.nameWithoutExtension, fontFamily = Mono, color = Dark.Ink)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RoundIcon(icon: @Composable () -> Unit, onClick: () -> Unit) {
    Box(Modifier.clip(CircleShape).background(Color(0x99000000))) {
        IconButton(onClick) { icon() }
    }
}

@Composable
private fun StatTile(label: String, value: String, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(16.dp)
    Column(modifier.clip(shape).background(Dark.Shade).border(1.dp, Dark.Hairline, shape).padding(horizontal = 12.dp, vertical = 10.dp)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = Dark.Faint, maxLines = 1)
        Spacer(Modifier.height(3.dp))
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = Dark.Ink,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A dialog in Yami's colours. */
@Composable
fun DarkDialog(title: String, onDismiss: () -> Unit, confirm: Pair<String, () -> Unit>, dismiss: Pair<String, () -> Unit>? = null,
               content: @Composable () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, containerColor = Dark.Shade, titleContentColor = Dark.Ink, textContentColor = Dark.Mist,
        shape = RoundedCornerShape(24.dp), tonalElevation = 0.dp,
        modifier = Modifier.border(1.dp, Dark.Hairline, RoundedCornerShape(24.dp)),
        title = { Text(title, style = MaterialTheme.typography.titleLarge) },
        text = content,
        confirmButton = { TextButton(confirm.second) { Text(confirm.first, color = MaterialTheme.colorScheme.primary) } },
        dismissButton = dismiss?.let { d -> { TextButton(d.second) { Text(d.first, color = Dark.Mist) } } })
}
