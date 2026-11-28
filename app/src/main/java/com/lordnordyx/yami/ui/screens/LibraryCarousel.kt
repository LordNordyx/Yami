package com.lordnordyx.yami.ui.screens

import android.os.Build
import android.view.KeyEvent as AndroidKey
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lordnordyx.yami.data.Game
import com.lordnordyx.yami.ui.Cover
import com.lordnordyx.yami.ui.GhostButton
import com.lordnordyx.yami.ui.PrimaryButton
import com.lordnordyx.yami.ui.formatPlaytime
import com.lordnordyx.yami.ui.theme.Dark
import com.lordnordyx.yami.ui.theme.PixelCaps
import com.lordnordyx.yami.ui.theme.PixelTitle
import kotlinx.coroutines.launch
import kotlin.math.absoluteValue

private fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t

/**
 * The game picker as a carousel: one big cover in focus, its neighbours
 * shrunk into the dark at the sides, the focused cover's art blurred behind.
 * D-pad / stick left-right flips, A plays, the buttons below for details.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LibraryCarousel(
    games: List<Game>,
    modifier: Modifier = Modifier,
    onPlay: (Game) -> Unit,
    onOpen: (Game) -> Unit,
    onFavorite: (Game) -> Unit,
) {
    if (games.isEmpty()) return
    // start on the game played last
    val start = remember(games.map { it.id }) {
        games.indices.maxByOrNull { games[it].lastPlayed }?.takeIf { games[it].lastPlayed > 0 } ?: 0
    }
    val pager = rememberPagerState(initialPage = start) { games.size }
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val current = games[pager.currentPage.coerceIn(0, games.size - 1)]

    BoxWithConstraints(modifier.fillMaxSize()) {
        // the focused cover, huge and blurred, sinking into black
        AnimatedContent(current.coverPath, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "bg") { path ->
            Box(Modifier.fillMaxSize()) {
                if (Build.VERSION.SDK_INT >= 31) {
                    Cover(path, "", Modifier.fillMaxSize().blur(48.dp).graphicsLayer { alpha = 0.45f }, fade = false)
                }
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
                    listOf(Color.Black.copy(alpha = 0.55f), Color.Black.copy(alpha = 0.25f), Color.Black))))
            }
        }

        val wide = maxWidth > maxHeight
        val infoH = 150.dp
        val cardH = ((maxHeight - infoH) * if (wide) 0.86f else 0.62f).coerceAtLeast(120.dp)
        val cardW = minOf(cardH * (4f / 3f), maxWidth * if (wide) 0.48f else 0.78f)
        val side = ((maxWidth - cardW) / 2).coerceAtLeast(0.dp)

        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
            HorizontalPager(
                state = pager,
                pageSize = PageSize.Fixed(cardW),
                contentPadding = PaddingValues(horizontal = side),
                pageSpacing = 18.dp,
                beyondViewportPageCount = 2,
                modifier = Modifier.fillMaxWidth().height(cardH + 24.dp)
                    .focusRequester(focus)
                    .onFocusChanged { focused = it.isFocused }
                    .onPreviewKeyEvent { e ->
                        val code = e.nativeKeyEvent.keyCode
                        val down = e.type == KeyEventType.KeyDown
                        when (code) {
                            AndroidKey.KEYCODE_DPAD_LEFT, AndroidKey.KEYCODE_BUTTON_L1 -> {
                                if (down) scope.launch { pager.animateScrollToPage((pager.currentPage - 1).coerceAtLeast(0)) }; true
                            }
                            AndroidKey.KEYCODE_DPAD_RIGHT, AndroidKey.KEYCODE_BUTTON_R1 -> {
                                if (down) scope.launch { pager.animateScrollToPage((pager.currentPage + 1).coerceAtMost(games.size - 1)) }; true
                            }
                            AndroidKey.KEYCODE_DPAD_CENTER, AndroidKey.KEYCODE_ENTER, AndroidKey.KEYCODE_BUTTON_A -> {
                                if (!down) onPlay(current); true
                            }
                            AndroidKey.KEYCODE_BUTTON_Y, AndroidKey.KEYCODE_BUTTON_X -> {
                                if (!down) onOpen(current); true
                            }
                            else -> false
                        }
                    }
                    .focusable(),
            ) { page ->
                val g = games[page]
                val offset = ((pager.currentPage - page) + pager.currentPageOffsetFraction).absoluteValue.coerceIn(0f, 1f)
                val shape = RoundedCornerShape(24.dp)
                val isCurrent = page == pager.currentPage
                Box(Modifier.fillMaxSize().padding(vertical = 12.dp)
                    .graphicsLayer {
                        val sc = lerp(1f, 0.78f, offset)
                        scaleX = sc; scaleY = sc
                        alpha = lerp(1f, 0.45f, offset)
                    }
                    .clip(shape)
                    .border(if (isCurrent && focused) 3.dp else 1.dp,
                        if (isCurrent && focused) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.14f), shape)
                    .combinedClickable(
                        onClick = { if (isCurrent) onPlay(g) else scope.launch { pager.animateScrollToPage(page) } },
                        onLongClick = { onFavorite(g) },
                    )) {
                    Cover(g.coverPath, g.title, Modifier.fillMaxSize())
                    if (g.favorite) Icon(Icons.Default.Star, "Favorite", Modifier.align(Alignment.TopEnd).padding(14.dp).size(22.dp),
                        tint = MaterialTheme.colorScheme.primary)
                }
            }

            // what's in focus
            Column(Modifier.fillMaxWidth().height(infoH).padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Spacer(Modifier.height(6.dp))
                AnimatedContent(current, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "info") { g ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(g.title, fontFamily = PixelTitle, fontSize = 26.sp, color = Dark.Ink, maxLines = 1,
                            overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                        Text("${g.engineHint.ifBlank { "RGSS" }}  ·  ${formatPlaytime(g.playTimeSec)}".uppercase(),
                            fontFamily = PixelCaps, fontSize = 10.sp, letterSpacing = 1.sp, color = Dark.Mist)
                    }
                }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    PrimaryButton("Play", { onPlay(current) }, icon = Icons.Default.PlayArrow, height = 48.dp)
                    GhostButton("Details", { onOpen(current) }, icon = Icons.Outlined.Info, height = 48.dp)
                    Text("${pager.currentPage + 1} / ${games.size}", fontFamily = PixelCaps, fontSize = 10.sp, color = Dark.Faint,
                        modifier = Modifier.padding(start = 6.dp))
                }
            }
        }
        // page dots
        if (games.size in 2..24) Row(Modifier.align(Alignment.TopCenter).padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            games.indices.forEach { i ->
                Box(Modifier.size(width = if (i == pager.currentPage) 14.dp else 5.dp, height = 5.dp).clip(CircleShape)
                    .background(if (i == pager.currentPage) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.18f)))
            }
        }
    }
}
