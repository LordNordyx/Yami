package com.lordnordyx.yami.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Gamepad
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.Vibration
import androidx.compose.material.icons.outlined.AutoFixHigh
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.lordnordyx.yami.BuildConfig
import com.lordnordyx.yami.ui.ActionRow
import com.lordnordyx.yami.ui.CrashDialog
import com.lordnordyx.yami.ui.EclipseMark
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.NavRow
import com.lordnordyx.yami.ui.Section
import com.lordnordyx.yami.ui.SectionNote
import com.lordnordyx.yami.ui.SwitchRow
import com.lordnordyx.yami.ui.Wordmark
import com.lordnordyx.yami.ui.YamiPage
import com.lordnordyx.yami.ui.focusRing
import com.lordnordyx.yami.ui.theme.ACCENTS
import com.lordnordyx.yami.ui.theme.Dark
import kotlinx.coroutines.launch
import java.io.File

/** The settings hub: everything is one level down. */
@Composable
fun SettingsScreen(vm: LibraryViewModel, back: () -> Unit, open: (String) -> Unit) {
    val s by vm.settings.collectAsState()
    val crash by vm.crashReport.collectAsState()
    CrashDialog(crash) { vm.crashReport.value = null }
    val accentName = ACCENTS.firstOrNull { it.argb == s.accent }?.name ?: "Custom"

    YamiPage("Settings", back) {
        Section(null) {
            NavRow("Appearance", "Accent of light against the dark", Icons.Outlined.Palette, value = accentName) { open("settings/appearance") }
            NavRow("Library", "Importing, gallery, haptics", Icons.Outlined.Collections) { open("settings/library") }
            NavRow("Controls", "Controllers, mapping, autofire, touch", Icons.Outlined.Gamepad) { open("controls") }
        }
        Section("Games") {
            NavRow("Game defaults", "Display, performance, speed-up, input, audio — for every game without its own settings",
                Icons.Outlined.Tune) { open("settings/defaults") }
            NavRow("Content", "RPG Maker RTP, SoundFont, shaders", Icons.Outlined.LibraryMusic) { open("settings/content") }
        }
        Section("Help") {
            ActionRow("Session log & crash report", "Engine output and system log — share it when reporting a problem",
                icon = Icons.Outlined.BugReport) { vm.showLastCrashReport() }
        }
        AboutCard()
    }
}

@Composable
private fun AboutCard() {
    Column(Modifier.fillMaxWidth().padding(top = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        EclipseMark(Modifier.size(56.dp))
        Spacer(Modifier.height(10.dp))
        Wordmark(18)
        Spacer(Modifier.height(4.dp))
        Text("RGSS player · ${BuildConfig.VERSION_NAME} · built on mkxp-z", style = MaterialTheme.typography.bodySmall, color = Dark.Faint)
    }
}

@Composable
fun AppearanceScreen(vm: LibraryViewModel, back: () -> Unit) {
    val s by vm.settings.collectAsState()
    YamiPage("Appearance", back) {
        // live preview of the accent
        Box(Modifier.fillMaxWidth().padding(16.dp).height(150.dp).clip(RoundedCornerShape(24.dp)).background(Dark.Void)
            .border(1.dp, Dark.Hairline, RoundedCornerShape(24.dp)), contentAlignment = Alignment.Center) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                EclipseMark(Modifier.size(84.dp), Color(s.accent))
                Spacer(Modifier.width(14.dp))
                Column {
                    Wordmark(24)
                    Text(ACCENTS.firstOrNull { it.argb == s.accent }?.name ?: "Custom", style = MaterialTheme.typography.labelSmall,
                        color = Color(s.accent))
                }
            }
        }
        Section("Accent") {
            ACCENTS.forEach { a ->
                val sel = a.argb == s.accent
                Row(Modifier.fillMaxWidth().focusRing(RoundedCornerShape(14.dp)).clickable { vm.updateApp { it.copy(accent = a.argb) } }.padding(horizontal = 18.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(28.dp).clip(CircleShape).background(Color(a.argb))
                        .then(if (sel) Modifier.border(2.dp, Dark.Ink, CircleShape) else Modifier))
                    Spacer(Modifier.width(16.dp))
                    Text(a.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f),
                        color = if (sel) Color(a.argb) else Dark.Ink)
                    if (sel) Icon(Icons.Default.Check, null, tint = Color(a.argb))
                }
            }
        }
        Section(null) { SectionNote("Yami is always pure black: on AMOLED screens black pixels are off, which saves battery and makes the dark truly dark.") }
    }
}

@Composable
fun LibrarySettingsScreen(vm: LibraryViewModel, back: () -> Unit) {
    val s by vm.settings.collectAsState()
    YamiPage("Library", back) {
        Section("Importing") {
            SwitchRow("Optimize on import", s.optimizeOnImport, "Unpack archives, index files and build compact tilesets automatically",
                Icons.Outlined.AutoFixHigh) { v -> vm.updateApp { it.copy(optimizeOnImport = v) } }
            SwitchRow("Hide game art from the gallery", s.hideFromGallery, "Adds .nomedia to every game folder",
                Icons.Outlined.Collections) { v -> vm.updateApp { it.copy(hideFromGallery = v) } }
        }
        Section("Feel") {
            SwitchRow("Haptic feedback", s.haptics, icon = Icons.Outlined.Vibration) { v -> vm.updateApp { it.copy(haptics = v) } }
        }
    }
}

@Composable
fun ContentScreen(vm: LibraryViewModel, back: () -> Unit) {
    val s by vm.settings.collectAsState()
    val scope = rememberCoroutineScope()
    val pickRtp = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { it?.let(vm::addRtp) }
    val pickShader = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(vm::importShader) }
    val pickSf2 = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch { vm.importSoundFont(uri)?.let { p -> vm.updateApp { it.copy(defaultSoundFont = p) } } }
    }
    YamiPage("Content", back) {
        Section("RPG Maker RTP") {
            SectionNote("Older RPG Maker XP games need the Standard RTP — graphics and audio they don't ship. Add the RTP folder once and every game can use it.")
            s.rtpPaths.forEach { p ->
                ActionRow(File(p).name, p, value = "Remove", danger = true) { vm.updateApp { it.copy(rtpPaths = it.rtpPaths - p) } }
            }
            ActionRow("Add RTP folder", icon = Icons.Outlined.FolderOpen) { pickRtp.launch(null) }
        }
        Section("Audio & shaders") {
            ActionRow("Default MIDI SoundFont", "Used by games without their own", icon = Icons.Outlined.LibraryMusic,
                value = s.defaultSoundFont.takeIf { it.isNotBlank() }?.let { File(it).name } ?: "Built-in") { pickSf2.launch(arrayOf("*/*")) }
            ActionRow("Import shader (.frag)", "GLSL ES fragment shader — see the shader guide in the README",
                icon = Icons.Outlined.AutoFixHigh) { pickShader.launch(arrayOf("*/*")) }
        }
    }
}

/** Global defaults: the category menu. */
@Composable
fun DefaultsScreen(vm: LibraryViewModel, back: () -> Unit, open: (SettingsCategory) -> Unit) {
    val s by vm.settings.collectAsState()
    YamiPage("Game defaults", back) {
        Section(null) { SectionNote("Every game uses these unless you give it its own settings on its page.") }
        SettingsCategoryList(s.defaults, null, open)
    }
}

@Composable
fun DefaultsCategoryScreen(vm: LibraryViewModel, cat: SettingsCategory, back: () -> Unit) {
    val s by vm.settings.collectAsState()
    YamiPage(cat.label, back) {
        SettingsCategoryContent(vm, cat, s.defaults) { f -> vm.updateApp { it.copy(defaults = f(it.defaults)) } }
    }
}

/** One game's settings: follow the defaults, or tune each category. */
@Composable
fun GameSettingsScreen(vm: LibraryViewModel, id: String, back: () -> Unit, open: (SettingsCategory) -> Unit) {
    val games by vm.repo.games.collectAsState()
    val app by vm.settings.collectAsState()
    val g = games.firstOrNull { it.id == id } ?: return
    YamiPage("${g.title}", back) {
        Section(null) {
            SwitchRow("Use game defaults", g.useGlobalSettings, "Turn off to tune this game separately") { vm.useGlobal(id, it) }
        }
        if (g.useGlobalSettings) {
            Section(null) { SectionNote("This game follows Settings → Game defaults. Turn the switch off to give it its own settings, starting from those defaults.") }
            Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(0.dp)) {
                SettingsCategoryList(app.defaults, "Current defaults") { open(it) }
            }
        } else {
            SettingsCategoryList(g.settings, "This game", open)
        }
    }
}

@Composable
fun GameSettingsCategoryScreen(vm: LibraryViewModel, id: String, cat: SettingsCategory, back: () -> Unit) {
    val games by vm.repo.games.collectAsState()
    val app by vm.settings.collectAsState()
    val g = games.firstOrNull { it.id == id } ?: return
    YamiPage(cat.label, back) {
        if (g.useGlobalSettings) {
            Section(null) { SectionNote("Changes here edit the game defaults, which every game without its own settings uses.") }
            SettingsCategoryContent(vm, cat, app.defaults) { f -> vm.updateApp { it.copy(defaults = f(it.defaults)) } }
        } else {
            SettingsCategoryContent(vm, cat, g.settings) { f -> vm.setGameSettings(id, f) }
        }
    }
}
