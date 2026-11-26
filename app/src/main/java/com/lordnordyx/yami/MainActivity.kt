package com.lordnordyx.yami

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import com.lordnordyx.yami.ui.LibraryViewModel
import com.lordnordyx.yami.ui.YamiNav
import com.lordnordyx.yami.ui.theme.YamiTheme

class MainActivity : ComponentActivity() {

    companion object {
        /** Sent by the engine process to relaunch a game in a fresh process. */
        const val EXTRA_RELAUNCH = "relaunch"
    }

    private val vm: LibraryViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleRelaunch(intent)
        setContent {
            YamiTheme(vm) { YamiNav(vm) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleRelaunch(intent)
    }

    override fun onResume() {
        super.onResume()
        vm.onReturnFromEngine()
    }

    private fun handleRelaunch(i: Intent?) {
        val id = i?.getStringExtra(EXTRA_RELAUNCH) ?: return
        i.removeExtra(EXTRA_RELAUNCH)
        // Let the old engine process finish dying before starting a new one.
        window.decorView.postDelayed({ vm.play(this, id, skipOptimize = true) }, 700)
    }
}
