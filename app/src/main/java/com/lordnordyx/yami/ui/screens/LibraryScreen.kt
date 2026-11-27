package com.lordnordyx.yami.ui.screens

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.FolderZip
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Sort
import androidx.compose.material.icons.outlined.ViewAgenda
import androidx.compose.material.icons.outlined.ViewList
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.lordnordyx.yami.data.Game
import com.lordnordyx.yami.data.LibrarySort
import com.lordnordyx.yami.data.LibraryView
import com.lordnordyx.yami.ui.BusyOverlay
import com.lordnordyx.yami.ui.Cover
import com.lordnordyx.yami.ui.CrashDialog
import com.lordnordyx.yami.ui.EclipseMark
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.OptionSheet
import com.lordnordyx.yami.ui.PrimaryButton
import com.lordnordyx.yami.ui.SheetHandle
import com.lordnordyx.yami.ui.Wordmark
import com.lordnordyx.yami.ui.formatPlaytime
import com.lordnordyx.yami.ui.theme.Dark

private enum class Filter(val label: String) { ALL("All"), FAVORITES("Favorites"), RECENT("Recent") }

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LibraryScreen(vm: LibraryViewModel, openGame: (String) -> Unit, openSettings: () -> Unit) {
    val ctx = LocalContext.current
    val all by vm.games.collectAsState()
    val settings by vm.settings.collectAsState()
    val busy by vm.busy.collectAsState()
    val msg by vm.message.collectAsState()
    val query by vm.query.collectAsState()
    val crash by vm.crashReport.collectAsState()
    val snack = remember { SnackbarHostState() }
    var addSheet by remember { mutableStateOf(false) }
    var sortSheet by remember { mutableStateOf(false) }
    var filter by remember { mutableStateOf(Filter.ALL) }
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

    val games = when (filter) {
        Filter.ALL -> all
        Filter.FAVORITES -> all.filter { it.favorite }
        Filter.RECENT -> all.filter { it.lastPlayed > 0 }.sortedByDescending { it.lastPlayed }
    }

    Scaffold(
        containerColor = Dark.Void,
        snackbarHost = {
            SnackbarHost(snack) { d ->
                Snackbar(d, containerColor = Dark.Dusk, contentColor = Dark.Ink, actionColor = MaterialTheme.colorScheme.primary,
                    shape = RoundedCornerShape(16.dp))
            }
        },
        floatingActionButton = {
            PrimaryButton("Add game", { addSheet = true }, Modifier.navigationBarsPadding(), icon = Icons.Default.Add, height = 54.dp)
        },
    ) { pad ->
        Box(Modifier.fillMaxSize().padding(bottom = pad.calculateBottomPadding())) {
            val view = settings.libraryView
            LazyVerticalGrid(
                columns = GridCells.Adaptive(when (view) { LibraryView.LIST -> 600.dp; LibraryView.COVERS -> 280.dp; LibraryView.GRID -> 150.dp }),
                contentPadding = PaddingValues(16.dp, 0.dp, 16.dp, 110.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Header(all.size, view,
                        cycleView = { vm.updateApp { it.copy(libraryView = LibraryView.entries[(view.ordinal + 1) % LibraryView.entries.size]) } },
                        openSort = { sortSheet = true }, openSettings = openSettings)
                }
                item(span = { GridItemSpan(maxLineSpan) }) { SearchPill(query) { vm.query.value = it } }
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 2.dp)) {
                        Filter.entries.forEach { f -> FilterPill(f.label, f == filter) { filter = f } }
                    }
                }
                val hero = all.filter { it.lastPlayed > 0 }.maxByOrNull { it.lastPlayed }
                if (hero != null && query.isBlank() && filter == Filter.ALL) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        HeroCard(hero, onPlay = { vm.play(ctx, hero.id) }, onOpen = { openGame(hero.id) })
                    }
                }
                if (games.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        EmptyState(when {
                            all.isEmpty() -> null
                            query.isNotBlank() -> "Nothing matches “$query”"
                            filter == Filter.FAVORITES -> "No favorites yet — long-press a game to add it"
                            else -> "Nothing played yet"
                        })
                    }
                } else {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Text(if (filter == Filter.ALL) "ALL GAMES" else filter.label.uppercase(), style = MaterialTheme.typography.labelSmall,
                            color = Dark.Mist, modifier = Modifier.padding(start = 4.dp, top = 8.dp))
                    }
                }
                items(games, key = { it.id }) { g ->
                    if (view == LibraryView.LIST) ListRow(g, { openGame(g.id) }, { vm.toggleFavorite(g.id) }, { vm.play(ctx, g.id) })
                    else GameCard(g, compact = view == LibraryView.GRID,
                        onClick = { openGame(g.id) }, onLongClick = { vm.toggleFavorite(g.id) }, onPlay = { vm.play(ctx, g.id) })
                }
            }
            BusyOverlay(busy, vm::cancel)
            CrashDialog(crash) { vm.crashReport.value = null }
        }
    }

    if (sortSheet) OptionSheet("Sort by", LibrarySort.entries, settings.sort, { it.label }, null, { sortSheet = false }) { s ->
        sortSheet = false; vm.updateApp { it.copy(sort = s) }
    }
    if (addSheet) AddGameSheet(onDismiss = { addSheet = false },
        importFolder = { addSheet = false; pickFolder.launch(null) },
        importZip = { addSheet = false; pickZip.launch(arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream")) },
        inPlace = { addSheet = false; needAllFiles("one") },
        scan = { addSheet = false; needAllFiles("scan") })
}

@Composable
private fun Header(count: Int, view: LibraryView, cycleView: () -> Unit, openSort: () -> Unit, openSettings: () -> Unit) {
    Row(Modifier.fillMaxWidth().statusBarsPadding().padding(top = 10.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        EclipseMark(Modifier.size(34.dp))
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Wordmark(22)
            Text(if (count == 1) "1 game" else "$count games", style = MaterialTheme.typography.bodySmall, color = Dark.Mist)
        }
        IconButton(cycleView) {
            Icon(when (view) {
                LibraryView.COVERS -> Icons.Outlined.ViewAgenda
                LibraryView.GRID -> Icons.Outlined.GridView
                LibraryView.LIST -> Icons.Outlined.ViewList
            }, "Change view", tint = Dark.Mist)
        }
        IconButton(openSort) { Icon(Icons.Outlined.Sort, "Sort", tint = Dark.Mist) }
        IconButton(openSettings) { Icon(Icons.Outlined.Settings, "Settings", tint = Dark.Mist) }
    }
}

@Composable
private fun SearchPill(query: String, onChange: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().height(50.dp).clip(CircleShape).background(Dark.Shade).border(1.dp, Dark.Hairline, CircleShape)
        .padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.Search, null, tint = Dark.Faint, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text("Search the dark", style = MaterialTheme.typography.bodyLarge, color = Dark.Faint)
            BasicTextField(query, onChange, singleLine = true, modifier = Modifier.fillMaxWidth(),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = Dark.Ink),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary))
        }
        if (query.isNotEmpty()) IconButton({ onChange("") }, Modifier.size(32.dp)) {
            Icon(Icons.Outlined.Close, "Clear", tint = Dark.Mist, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun FilterPill(label: String, selected: Boolean, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Box(Modifier.clip(CircleShape)
        .background(if (selected) accent.copy(alpha = 0.14f) else Color.Transparent)
        .border(1.dp, if (selected) accent.copy(alpha = 0.6f) else Dark.Hairline, CircleShape)
        .clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = if (selected) accent else Dark.Mist)
    }
}

@Composable
private fun HeroCard(g: Game, onPlay: () -> Unit, onOpen: () -> Unit) {
    val shape = RoundedCornerShape(26.dp)
    Box(Modifier.fillMaxWidth().height(230.dp).clip(shape).border(1.dp, Dark.Hairline, shape).clickable(onClick = onOpen)) {
        Cover(g.coverPath, g.title, Modifier.fillMaxSize())
        Column(Modifier.align(Alignment.BottomStart).padding(20.dp).padding(end = 120.dp)) {
            Text("CONTINUE", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(4.dp))
            Text(g.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold,
                maxLines = 1, overflow = TextOverflow.Ellipsis, color = Dark.Ink)
            Text("${formatPlaytime(g.playTimeSec)} · ${g.engineHint}", style = MaterialTheme.typography.bodySmall, color = Dark.Mist)
        }
        PrimaryButton("Play", onPlay, Modifier.align(Alignment.BottomEnd).padding(18.dp), icon = Icons.Default.PlayArrow, height = 48.dp)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GameCard(g: Game, compact: Boolean, onClick: () -> Unit, onLongClick: () -> Unit, onPlay: () -> Unit) {
    val shape = RoundedCornerShape(if (compact) 18.dp else 22.dp)
    Column(Modifier.clip(shape).background(Dark.Shade).border(1.dp, Dark.Hairline, shape)
        .combinedClickable(onClick = onClick, onLongClick = onLongClick, onDoubleClick = onPlay)) {
        Box(Modifier.fillMaxWidth().aspectRatio(4f / 3f)) {
            Cover(g.coverPath, g.title, Modifier.fillMaxSize())
            if (g.favorite) Icon(Icons.Default.Star, "Favorite", Modifier.align(Alignment.TopEnd).padding(10.dp).size(18.dp),
                tint = MaterialTheme.colorScheme.primary)
            if (!compact) Box(Modifier.align(Alignment.BottomEnd).padding(10.dp).size(42.dp).clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary).clickable(onClick = onPlay), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.PlayArrow, "Play", tint = Dark.Void)
            }
        }
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            Text(g.title, style = MaterialTheme.typography.titleSmall, color = Dark.Ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (!compact) Text("${g.engineHint} · ${formatPlaytime(g.playTimeSec)}", style = MaterialTheme.typography.bodySmall,
                color = Dark.Mist, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ListRow(g: Game, onClick: () -> Unit, onLongClick: () -> Unit, onPlay: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Row(Modifier.fillMaxWidth().clip(shape).background(Dark.Shade).border(1.dp, Dark.Hairline, shape)
        .combinedClickable(onClick = onClick, onLongClick = onLongClick).padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Cover(g.coverPath, g.title, Modifier.size(width = 92.dp, height = 69.dp).clip(RoundedCornerShape(12.dp)), fade = false)
        Column(Modifier.weight(1f).padding(horizontal = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(g.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false))
                if (g.favorite) Icon(Icons.Default.Star, null, Modifier.padding(start = 6.dp).size(14.dp), tint = MaterialTheme.colorScheme.primary)
            }
            Text("${g.engineHint} · ${formatPlaytime(g.playTimeSec)}", style = MaterialTheme.typography.bodySmall, color = Dark.Mist)
        }
        Box(Modifier.size(40.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary).clickable(onClick = onPlay),
            contentAlignment = Alignment.Center) { Icon(Icons.Default.PlayArrow, "Play", tint = Dark.Void) }
    }
}

@Composable
private fun EmptyState(message: String?) {
    Column(Modifier.fillMaxWidth().padding(vertical = 56.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        EclipseMark(Modifier.size(if (message == null) 120.dp else 72.dp))
        Spacer(Modifier.height(18.dp))
        if (message == null) {
            Text("Nothing in the dark yet", style = MaterialTheme.typography.titleLarge, color = Dark.Ink)
            Spacer(Modifier.height(6.dp))
            Text("Add an RPG Maker XP, VX or VX Ace game — a folder or a .zip.\nYami unpacks archives, indexes files and prepares maps on import.",
                style = MaterialTheme.typography.bodyMedium, color = Dark.Mist, textAlign = TextAlign.Center)
        } else {
            Text(message, style = MaterialTheme.typography.bodyMedium, color = Dark.Mist, textAlign = TextAlign.Center)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddGameSheet(onDismiss: () -> Unit, importFolder: () -> Unit, importZip: () -> Unit, inPlace: () -> Unit, scan: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Dark.Abyss, scrimColor = Color(0xCC000000), dragHandle = { SheetHandle() }) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 16.dp)) {
            Text("Add a game", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            AddOption(Icons.Outlined.FolderOpen, "Play in place", "Uses the folder where it is — no copy, saves stay with the game. Best for SD cards", inPlace)
            AddOption(Icons.Outlined.ManageSearch, "Scan a folder of games", "Adds every game found inside, in place", scan)
            AddOption(Icons.Outlined.CreateNewFolder, "Import a folder", "Copies the game into Yami's storage", importFolder)
            AddOption(Icons.Outlined.FolderZip, "Import a .zip", "Unpacks the archive into Yami's storage", importZip)
        }
    }
}

@Composable
private fun AddOption(icon: ImageVector, title: String, desc: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 24.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(42.dp).clip(RoundedCornerShape(13.dp)).background(Dark.Dusk), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
        }
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(desc, style = MaterialTheme.typography.bodySmall, color = Dark.Mist)
        }
    }
}
