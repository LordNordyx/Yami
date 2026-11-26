package com.lordnordyx.yami.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lordnordyx.yami.ui.ActionRow
import com.lordnordyx.yami.ui.BusyOverlay
import com.lordnordyx.yami.ui.Cover
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.Section
import com.lordnordyx.yami.ui.SwitchRow
import com.lordnordyx.yami.ui.formatPlaytime
import com.lordnordyx.yami.ui.theme.Mono
import java.text.DateFormat
import java.util.Date

@Composable
fun GameDetailScreen(vm: LibraryViewModel, id: String, back: () -> Unit) {
    val ctx = LocalContext.current
    val games by vm.repo.games.collectAsState()
    val busy by vm.busy.collectAsState()
    val g = games.firstOrNull { it.id == id } ?: run { Text("Game not found"); return }
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

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Box(Modifier.fillMaxWidth().height(280.dp)) {
                Cover(g.coverPath, g.title, Modifier.fillMaxSize())
                IconButton(back, Modifier.padding(top = 32.dp, start = 8.dp)) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                IconButton({ vm.toggleFavorite(id) }, Modifier.align(Alignment.TopEnd).padding(top = 32.dp, end = 8.dp)) {
                    Icon(if (g.favorite) Icons.Default.Star else Icons.Default.StarBorder, "Favorite", tint = MaterialTheme.colorScheme.primary)
                }
                Column(Modifier.align(Alignment.BottomStart).padding(20.dp)) {
                    Text(g.engineHint.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    Text(g.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
                }
            }
            Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Button({ vm.play(ctx, id) }, Modifier.weight(1f).height(52.dp)) {
                    Icon(Icons.Default.PlayArrow, null); Spacer(Modifier.width(8.dp)); Text("Play", fontWeight = FontWeight.Bold)
                }
                FilledTonalButton({ vm.optimize(id, thenPlay = false, ctx = ctx) }, Modifier.height(52.dp)) {
                    Text(if (g.optimize == null) "Optimize" else "Re-optimize")
                }
            }
            Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Stat("Played", formatPlaytime(g.playTimeSec))
                Stat("Last", if (g.lastPlayed > 0) DateFormat.getDateInstance(DateFormat.SHORT).format(Date(g.lastPlayed)) else "—")
                Stat("Launches", g.launches.toString())
                Stat("Engine", "RGSS${g.rgssVersion}")
            }
            Spacer(Modifier.height(8.dp))

            g.optimize?.let { o ->
                Section("Optimization") {
                    ActionRow("Status", o.note.ifBlank { "Ready" })
                    ActionRow("Resource index", value = "${o.indexedFiles} files") {}
                    ActionRow("Maps", value = "${o.maps} · ${o.mapBytes / 1024} KiB") {}
                    if (o.optimizedTilesets > 0) ActionRow("Compact tilesets", value = "${o.mapVariants} from ${o.optimizedTilesets}") {}
                    if (o.savedPixels > 0) ActionRow("Texture memory saved", value = "${o.savedPixels * 4 / (1024 * 1024)} MB") {}
                    if (o.archiveExtracted) ActionRow("Restore original archive", "Removes unpacked files, puts Game.rgssad back") { vm.restoreArchive(id) }
                    ActionRow("Delete optimized maps") { vm.deleteOptimized(id) }
                }
            }

            Section("Saves") {
                ActionRow("Manage saves", "Snapshots are taken before every launch", value = "${vm.saves.list(g).size} files") { showSaves = true }
                ActionRow("Export saves (.zip)") { exportSaves.launch("${g.title} saves.zip") }
                ActionRow("Import saves (.zip)") { importSaves.launch(arrayOf("application/zip", "application/octet-stream")) }
            }

            Section("Settings") {
                SwitchRow("Use global settings", g.useGlobalSettings, "Turn off to tune this game separately") { vm.useGlobal(id, it) }
            }
            if (!g.useGlobalSettings) SettingsEditor(vm, g.settings) { f -> vm.setGameSettings(id, f) }

            Section("Library") {
                ActionRow("Rename") { renaming = true }
                ActionRow("Location", value = g.path.substringAfterLast('/')) {}
                ActionRow("Remove from library") { confirmRemove = true }
            }
            Spacer(Modifier.height(48.dp))
        }
        BusyOverlay(busy, vm::cancel)
    }

    if (renaming) {
        var t by remember { mutableStateOf(g.title) }
        AlertDialog({ renaming = false }, confirmButton = { TextButton({ vm.rename(id, t); renaming = false }) { Text("Save") } },
            dismissButton = { TextButton({ renaming = false }) { Text("Cancel") } },
            title = { Text("Rename") }, text = { OutlinedTextField(t, { t = it }, singleLine = true) })
    }
    if (confirmRemove) {
        AlertDialog({ confirmRemove = false },
            title = { Text("Remove ${g.title}?") },
            text = { Text(if (g.inPlace) "The game folder stays where it is. Yami's saves for it are deleted." else "Deletes the imported copy and Yami's saves for it. Export saves first if you want to keep them.") },
            confirmButton = { TextButton({ vm.remove(id, deleteFiles = true); confirmRemove = false; back() }) { Text("Remove") } },
            dismissButton = { TextButton({ vm.remove(id, deleteFiles = false); confirmRemove = false; back() }) { Text("Keep files") } })
    }
    if (showSaves) {
        val snaps = remember(refresh) { vm.saves.snapshots(g) }
        val files = remember(refresh) { vm.saves.list(g) }
        AlertDialog({ showSaves = false }, confirmButton = { TextButton({ showSaves = false }) { Text("Close") } },
            title = { Text("Saves") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    if (files.isEmpty()) Text("No saves yet")
                    files.forEach { Text("${it.file.name}  ·  ${it.location}", fontFamily = Mono, style = MaterialTheme.typography.bodySmall) }
                    if (snaps.isNotEmpty()) {
                        Spacer(Modifier.height(12.dp))
                        Text("Snapshots (tap to restore)", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                        snaps.forEach { z ->
                            TextButton({ vm.saves.restore(g, z); refresh++; vm.message.value = "Restored ${z.nameWithoutExtension}" }) {
                                Text(z.nameWithoutExtension, fontFamily = Mono)
                            }
                        }
                    }
                }
            })
    }
}

@Composable
private fun Stat(label: String, value: String) {
    Column {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontFamily = Mono, fontWeight = FontWeight.Bold)
    }
}
