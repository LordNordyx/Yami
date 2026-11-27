package com.lordnordyx.yami.ui

import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.lordnordyx.yami.ui.screens.AppearanceScreen
import com.lordnordyx.yami.ui.screens.ContentScreen
import com.lordnordyx.yami.ui.screens.ControlsScreen
import com.lordnordyx.yami.ui.screens.DefaultsCategoryScreen
import com.lordnordyx.yami.ui.screens.DefaultsScreen
import com.lordnordyx.yami.ui.screens.GameDetailScreen
import com.lordnordyx.yami.ui.screens.GameSettingsCategoryScreen
import com.lordnordyx.yami.ui.screens.GameSettingsScreen
import com.lordnordyx.yami.ui.screens.LibraryScreen
import com.lordnordyx.yami.ui.screens.LibrarySettingsScreen
import com.lordnordyx.yami.ui.screens.SettingsCategory
import com.lordnordyx.yami.ui.screens.SettingsScreen
import com.lordnordyx.yami.ui.theme.Dark

@Composable
fun YamiNav(vm: LibraryViewModel) {
    val nav = rememberNavController()
    val back: () -> Unit = { nav.popBackStack() }
    fun cat(name: String?) = SettingsCategory.entries.firstOrNull { it.name == name } ?: SettingsCategory.DISPLAY
    Box(Modifier.fillMaxSize().background(Dark.Void)) {
        NavHost(nav, startDestination = "library",
            // out of the dark: a short fade with a slight drift
            enterTransition = { fadeIn(tween(220)) + slideInHorizontally(tween(220)) { it / 12 } },
            exitTransition = { fadeOut(tween(160)) },
            popEnterTransition = { fadeIn(tween(220)) },
            popExitTransition = { fadeOut(tween(160)) + slideOutHorizontally(tween(200)) { it / 12 } },
        ) {
            composable("library") {
                LibraryScreen(vm,
                    openGame = { nav.navigate("game/$it") },
                    openSettings = { nav.navigate("settings") })
            }
            composable("game/{id}", arguments = listOf(navArgument("id") { type = NavType.StringType })) { e ->
                val id = e.arguments?.getString("id") ?: ""
                GameDetailScreen(vm, id, back = back, openSettings = { nav.navigate("game/$id/settings") })
            }
            composable("game/{id}/settings", arguments = listOf(navArgument("id") { type = NavType.StringType })) { e ->
                val id = e.arguments?.getString("id") ?: ""
                GameSettingsScreen(vm, id, back) { c -> nav.navigate("game/$id/settings/${c.name}") }
            }
            composable("game/{id}/settings/{cat}", arguments = listOf(
                navArgument("id") { type = NavType.StringType }, navArgument("cat") { type = NavType.StringType })) { e ->
                GameSettingsCategoryScreen(vm, e.arguments?.getString("id") ?: "", cat(e.arguments?.getString("cat")), back)
            }
            composable("settings") { SettingsScreen(vm, back) { route -> nav.navigate(route) } }
            composable("settings/appearance") { AppearanceScreen(vm, back) }
            composable("settings/library") { LibrarySettingsScreen(vm, back) }
            composable("settings/content") { ContentScreen(vm, back) }
            composable("settings/defaults") { DefaultsScreen(vm, back) { c -> nav.navigate("settings/defaults/${c.name}") } }
            composable("settings/defaults/{cat}", arguments = listOf(navArgument("cat") { type = NavType.StringType })) { e ->
                DefaultsCategoryScreen(vm, cat(e.arguments?.getString("cat")), back)
            }
            composable("controls") { ControlsScreen(vm, back) }
        }
    }
}
