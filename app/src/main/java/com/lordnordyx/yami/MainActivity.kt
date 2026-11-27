package com.lordnordyx.yami

import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
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

    /**
     * Controllers: A selects and B goes back everywhere in the app (the
     * library, settings, sheets, dialogs), whatever the device's own key
     * mapping does with gamepad buttons.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val mapped = when (event.keyCode) {
            KeyEvent.KEYCODE_BUTTON_A -> KeyEvent.KEYCODE_DPAD_CENTER
            KeyEvent.KEYCODE_BUTTON_B -> KeyEvent.KEYCODE_BACK
            else -> return super.dispatchKeyEvent(event)
        }
        return super.dispatchKeyEvent(KeyEvent(event.downTime, event.eventTime, event.action, mapped, event.repeatCount,
            event.metaState, event.deviceId, event.scanCode, event.flags, event.source))
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
        // play() waits for the old engine process to exit before starting a new one.
        vm.play(this, id, skipOptimize = true)
    }
}
