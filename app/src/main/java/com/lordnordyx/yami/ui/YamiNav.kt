package com.lordnordyx.yami.ui

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.lordnordyx.yami.ui.screens.ControlsScreen
import com.lordnordyx.yami.ui.screens.GameDetailScreen
import com.lordnordyx.yami.ui.screens.LibraryScreen
import com.lordnordyx.yami.ui.screens.SettingsScreen

@Composable
fun YamiNav(vm: LibraryViewModel) {
    val nav = rememberNavController()
    NavHost(nav, startDestination = "library") {
        composable("library") {
            LibraryScreen(vm,
                openGame = { nav.navigate("game/$it") },
                openSettings = { nav.navigate("settings") },
                openControls = { nav.navigate("controls") })
        }
        composable("game/{id}", arguments = listOf(navArgument("id") { type = NavType.StringType })) { e ->
            GameDetailScreen(vm, e.arguments?.getString("id") ?: "", back = { nav.popBackStack() })
        }
        composable("settings") { SettingsScreen(vm, back = { nav.popBackStack() }, openControls = { nav.navigate("controls") }) }
        composable("controls") { ControlsScreen(vm, back = { nav.popBackStack() }) }
    }
}
