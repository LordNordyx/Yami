package com.lordnordyx.yami.ui.screens

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Sort
import androidx.compose.material.icons.outlined.ViewAgenda
import androidx.compose.material.icons.outlined.ViewList
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.lordnordyx.yami.data.Game
import com.lordnordyx.yami.data.LibrarySort
import com.lordnordyx.yami.data.LibraryView
import com.lordnordyx.yami.ui.BusyOverlay
import com.lordnordyx.yami.ui.CrashDialog
import com.lordnordyx.yami.ui.Cover
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.formatPlaytime
import com.lordnordyx.yami.ui.theme.Mono

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LibraryScreen(vm: LibraryViewModel, openGame: (String) -> Unit, openSettings: () -> Unit, openControls: () -> Unit) {
    val ctx = LocalContext.current
    val games by vm.games.collectAsState()
    val settings by vm.settings.collectAsState()
    val busy by vm.busy.collectAsState()
    val msg by vm.message.collectAsState()
    val query by vm.query.collectAsState()
    val crash by vm.crashReport.collectAsState()
    val snack = remember { SnackbarHostState() }
    var addMenu by remember { mutableStateOf(false) }
    var sortMenu by remember { mutableStateOf(false) }
    var pendingInPlace by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(msg) { msg?.let { snack.showSnackbar(it); vm.message.value = null } }

    val pickFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { it?.let(vm::importFolder) }
    val pickZip = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(vm::importZip) }
    val pickInPlace = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        if (pendingInPlace == "scan") vm.scanFolder(uri) else vm.addInPlace(uri)
    }
    fun needAllFiles(mode: String) {
        pendingInPlace = mode
        if (Build.VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager()) {
            ctx.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${ctx.packageName}")))
            vm.message.value = "Allow \"All files access\", then choose the folder again"
        } else pickInPlace.launch(null)
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snack) },
        floatingActionButton = {
            Box {
                ExtendedFloatingActionButton(onClick = { addMenu = true }, icon = { Icon(Icons.Default.Add, null) }, text = { Text("Add game") })
                DropdownMenu(addMenu, { addMenu = false }) {
                    DropdownMenuItem({ Text("Import folder (copy)") }, { addMenu = false; pickFolder.launch(null) })
                    DropdownMenuItem({ Text("Import .zip") }, { addMenu = false; pickZip.launch(arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream")) })
                    DropdownMenuItem({ Text("Play in place (no copy)") }, { addMenu = false; needAllFiles("one") })
                    DropdownMenuItem({ Text("Scan a folder of games") }, { addMenu = false; needAllFiles("scan") })
                }
            }
        },
    ) { pad ->
        Box(Modifier.fillMaxSize().padding(pad)) {
            val cols = when (settings.libraryView) { LibraryView.COVERS -> 2; LibraryView.GRID -> 4; LibraryView.LIST -> 1 }
            LazyVerticalGrid(
                columns = GridCells.Adaptive(if (cols == 1) 600.dp else if (cols == 2) 280.dp else 150.dp),
                contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 8.dp)) {
                        Column(Modifier.weight(1f)) {
                            Text("Yami", style = MaterialTheme.typography.headlineLarge)
                            Text("${games.size} games · RGSS player", style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        IconButton({
                            val next = LibraryView.entries[(settings.libraryView.ordinal + 1) % LibraryView.entries.size]
                            vm.updateApp { it.copy(libraryView = next) }
                        }) {
                            Icon(when (settings.libraryView) {
                                LibraryView.COVERS -> Icons.Outlined.ViewAgenda
                                LibraryView.GRID -> Icons.Outlined.GridView
                                LibraryView.LIST -> Icons.Outlined.ViewList
                            }, "View")
                        }
                        Box {
                            IconButton({ sortMenu = true }) { Icon(Icons.Outlined.Sort, "Sort") }
                            DropdownMenu(sortMenu, { sortMenu = false }) {
                                LibrarySort.entries.forEach { s ->
                                    DropdownMenuItem({ Text(s.label, fontWeight = if (s == settings.sort) FontWeight.Bold else null) },
                                        { sortMenu = false; vm.updateApp { it.copy(sort = s) } })
                                }
                            }
                        }
                        IconButton(openControls) { Icon(Icons.Outlined.SportsEsports, "Controls") }
                        IconButton(openSettings) { Icon(Icons.Outlined.Settings, "Settings") }
                    }
                }
                item(span = { GridItemSpan(maxLineSpan) }) {
                    OutlinedTextField(query, { vm.query.value = it }, Modifier.fillMaxWidth(), singleLine = true,
                        placeholder = { Text("Search games") }, shape = RoundedCornerShape(16.dp))
                }
                val hero = games.filter { it.lastPlayed > 0 }.maxByOrNull { it.lastPlayed }
                if (hero != null && query.isBlank()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        HeroCard(hero, onPlay = { vm.play(ctx, hero.id) }, onOpen = { openGame(hero.id) })
                    }
                }
                if (games.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) { EmptyState() }
                }
                items(games, key = { it.id }) { g ->
                    if (settings.libraryView == LibraryView.LIST) ListRow(g, { openGame(g.id) }, { vm.play(ctx, g.id) })
                    else GameCard(g, compact = settings.libraryView == LibraryView.GRID,
                        onClick = { openGame(g.id) }, onLongClick = { vm.toggleFavorite(g.id) }, onPlay = { vm.play(ctx, g.id) })
                }
            }
            BusyOverlay(busy, vm::cancel)
            CrashDialog(crash) { vm.crashReport.value = null }
        }
    }
}

@Composable
private fun HeroCard(g: Game, onPlay: () -> Unit, onOpen: () -> Unit) {
    Card(onClick = onOpen, shape = RoundedCornerShape(24.dp), modifier = Modifier.fillMaxWidth().height(220.dp)) {
        Box {
            Cover(g.coverPath, g.title, Modifier.fillMaxSize())
            Column(Modifier.align(Alignment.BottomStart).padding(20.dp)) {
                Text("CONTINUE", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                Text(g.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${formatPlaytime(g.playTimeSec)} · ${g.engineHint}", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Button(onPlay, Modifier.align(Alignment.BottomEnd).padding(20.dp)) {
                Icon(Icons.Default.PlayArrow, null); Spacer(Modifier.width(6.dp)); Text("Play")
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GameCard(g: Game, compact: Boolean, onClick: () -> Unit, onLongClick: () -> Unit, onPlay: () -> Unit) {
    Card(shape = RoundedCornerShape(20.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        modifier = Modifier.clip(RoundedCornerShape(20.dp)).combinedClickable(onClick = onClick, onLongClick = onLongClick, onDoubleClick = onPlay)) {
        Box(Modifier.fillMaxWidth().aspectRatio(4f / 3f)) {
            Cover(g.coverPath, g.title, Modifier.fillMaxSize())
            if (g.favorite) Icon(Icons.Default.Star, "Favorite", Modifier.align(Alignment.TopEnd).padding(10.dp).size(18.dp),
                tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.align(Alignment.BottomStart).padding(12.dp)) {
                Text(g.title, fontWeight = FontWeight.Bold, maxLines = if (compact) 1 else 2, overflow = TextOverflow.Ellipsis)
                if (!compact) Text(g.engineHint, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (!compact) IconButton(onPlay, Modifier.align(Alignment.BottomEnd)) {
                Icon(Icons.Default.PlayArrow, "Play", tint = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

@Composable
private fun ListRow(g: Game, onClick: () -> Unit, onPlay: () -> Unit) {
    Card(onClick = onClick, shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
        Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Cover(g.coverPath, g.title, Modifier.size(width = 96.dp, height = 72.dp).clip(RoundedCornerShape(10.dp)))
            Column(Modifier.weight(1f).padding(horizontal = 14.dp)) {
                Text(g.title, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${g.engineHint} · ${formatPlaytime(g.playTimeSec)}", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onPlay) { Icon(Icons.Default.PlayArrow, "Play", tint = MaterialTheme.colorScheme.primary) }
        }
    }
}

@Composable
private fun EmptyState() {
    Column(Modifier.fillMaxWidth().padding(vertical = 64.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("> no games yet_", fontFamily = Mono, style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.primary)
        Text("Add an RPG Maker XP, VX or VX Ace game folder or .zip.\nYami unpacks archives, indexes files and optimizes maps on import.",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
