package com.lordnordyx.yami.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.lordnordyx.yami.BuildConfig
import com.lordnordyx.yami.ui.ActionRow
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.Section
import com.lordnordyx.yami.ui.SwitchRow
import kotlinx.coroutines.launch
import java.io.File

private val ACCENTS = listOf(0xFF7C5CFF, 0xFF38E1C5, 0xFFFF5C8A, 0xFFFFB020, 0xFF4DA3FF, 0xFFE6E6E6)

@Composable
fun SettingsScreen(vm: LibraryViewModel, back: () -> Unit, openControls: () -> Unit) {
    val s by vm.settings.collectAsState()
    val scope = rememberCoroutineScope()
    val pickRtp = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { it?.let(vm::addRtp) }
    val pickShader = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(vm::importShader) }
    val pickSf2 = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch { vm.importSoundFont(uri)?.let { p -> vm.updateApp { it.copy(defaultSoundFont = p) } } }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 32.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(8.dp)) {
            IconButton(back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Text("Settings", style = MaterialTheme.typography.headlineMedium)
        }

        Section("Appearance") {
            Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                ACCENTS.forEach { c ->
                    val sel = s.accent == c
                    Spacer(Modifier.size(34.dp).background(Color(c), CircleShape)
                        .then(if (sel) Modifier.border(3.dp, Color.White, CircleShape) else Modifier)
                        .clickable { vm.updateApp { it.copy(accent = c) } })
                }
            }
            SwitchRow("Pure black (AMOLED)", s.amoled) { v -> vm.updateApp { it.copy(amoled = v) } }
        }
        Section("Library") {
            SwitchRow("Optimize on import", s.optimizeOnImport, "Unpack archives, index files and build compact tilesets automatically") { v -> vm.updateApp { it.copy(optimizeOnImport = v) } }
            SwitchRow("Hide game art from gallery", s.hideFromGallery, "Adds .nomedia to each game folder") { v -> vm.updateApp { it.copy(hideFromGallery = v) } }
            SwitchRow("Haptic feedback", s.haptics) { v -> vm.updateApp { it.copy(haptics = v) } }
        }
        Section("RPG Maker RTP") {
            Text("Older RMXP games need the Standard RTP (graphics and audio they don't ship). Add the RTP folder once and every game can use it.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            s.rtpPaths.forEach { p ->
                ActionRow(File(p).name, p, value = "Remove") { vm.updateApp { it.copy(rtpPaths = it.rtpPaths - p) } }
            }
            ActionRow("Add RTP folder") { pickRtp.launch(null) }
        }
        Section("Audio & shaders") {
            ActionRow("Default MIDI SoundFont", value = s.defaultSoundFont.takeIf { it.isNotBlank() }?.let { File(it).name } ?: "Built-in") { pickSf2.launch(arrayOf("*/*")) }
            ActionRow("Import shader (.frag)", "GLSL ES fragment shader; see the shader guide in the README") { pickShader.launch(arrayOf("*/*")) }
        }
        Section("Controls") {
            ActionRow("Controllers & touch", "Auto-binding, remapping, autofire, live test") { openControls() }
        }
        Text("DEFAULTS FOR ALL GAMES", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 20.dp, top = 16.dp))
        SettingsEditor(vm, s.defaults) { f -> vm.updateApp { it.copy(defaults = f(it.defaults)) } }

        Section("About") {
            ActionRow("Yami", "RGSS player for Android, built on mkxp-z", value = BuildConfig.VERSION_NAME)
        }
        Spacer(Modifier.height(48.dp))
    }
}
