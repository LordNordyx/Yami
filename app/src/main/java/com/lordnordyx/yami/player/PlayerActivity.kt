package com.lordnordyx.yami.player

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.hardware.input.InputManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.system.Os
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.widget.Toast
import com.lordnordyx.yami.MainActivity
import com.lordnordyx.yami.data.Game
import com.lordnordyx.yami.data.GameRepository
import com.lordnordyx.yami.data.GameSettings
import com.lordnordyx.yami.data.SaveManager
import com.lordnordyx.yami.engine.EngineConfig
import com.lordnordyx.yami.input.ControllerMapper
import com.lordnordyx.yami.input.InputConfig
import com.lordnordyx.yami.input.KeyInjector
import com.lordnordyx.yami.input.RgssButton
import com.lordnordyx.yami.input.TouchControlsView
import org.libsdl.app.SDLActivity
import java.io.File
import kotlin.system.exitProcess

/**
 * Hosts the mkxp-z engine. Runs in the ":engine" process so every launch gets
 * a fresh native state and an engine crash never takes the library with it.
 */
class PlayerActivity : SDLActivity(), InputManager.InputDeviceListener {

    companion object {
        const val EXTRA_GAME_ID = "game_id"
        const val EXTRA_OPTIMIZE = "optimize"

        fun launch(ctx: Context, gameId: String, optimize: Boolean = false) {
            ctx.startActivity(Intent(ctx, PlayerActivity::class.java)
                .putExtra(EXTRA_GAME_ID, gameId)
                .putExtra(EXTRA_OPTIMIZE, optimize)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    private lateinit var repo: GameRepository
    private var game: Game? = null
    private lateinit var settings: GameSettings
    private lateinit var inputConfig: InputConfig
    private var optimizeMode = false

    private lateinit var injector: KeyInjector
    private lateinit var mapper: ControllerMapper
    private var touch: TouchControlsView? = null
    private var info: InfoOverlayView? = null
    private var menu: QuickMenuView? = null
    private var logView: LogOverlayView? = null
    private var watchdog: MainThreadWatchdog? = null
    private var status: EngineStatus? = null
    private var turboActive = false

    private var resumedAt = 0L
    private var usingController = false
    private val accent = 0xFF7C5CFF.toInt()

    // ------------------------------------------------------------- SDL hooks
    override fun getLibraries(): Array<String> = arrayOf("main")
    override fun getArguments(): Array<String> = emptyArray()

    override fun onCreate(savedInstanceState: Bundle?) {
        repo = GameRepository(applicationContext, owner = false)
        val id = intent.getStringExtra(EXTRA_GAME_ID)
        game = id?.let { repo.game(it) }
        optimizeMode = intent.getBooleanExtra(EXTRA_OPTIMIZE, false)
        val g = game
        if (g == null || !File(g.path).isDirectory) {
            super.onCreate(savedInstanceState)
            Toast.makeText(this, "Game folder not found", Toast.LENGTH_LONG).show()
            finish()
            return
        }
        CrashReports.beginSession(this, g.id, g.title)
        settings = repo.effectiveSettings(g)
        inputConfig = InputConfig.load(this)

        if (!optimizeMode) runCatching { SaveManager(this, repo).snapshot(g) }
        val prepared = try {
            EngineConfig.prepare(this, repo, g, displayAspect(), optimizeMode)
        } catch (t: Throwable) {
            // Report it in the library instead of dying silently.
            runCatching { java.io.File(filesDir, "logs/java-crash.txt").writeText("Preparing the game failed\n${t.stackTraceToString()}") }
            super.onCreate(savedInstanceState)
            Toast.makeText(this, "Couldn't start the game: ${t.message}", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        // Everything the native side reads at startup goes through the environment,
        // which must be set before SDLActivity loads libmain and starts SDL_main.
        Os.setenv("SRCDIR", prepared.gameDir.absolutePath, true)
        Os.setenv("YAMI_CFG", prepared.cfgFile.absolutePath, true)
        Os.setenv("YAMI_DATA_DIR", prepared.dataDir.absolutePath, true)
        Os.setenv("SDL_ANDROID_TRAP_BACK_BUTTON", "1", true)
        // Decoded-image cache in the engine ("" = automatic budget, 0 = off)
        Os.setenv("YAMI_IMAGE_CACHE_MB", if (settings.graphicsCache) "" else "0", true)
        // Ruby GC: Essentials allocates heavily every frame; a bigger starting
        // heap and malloc limits mean far fewer collections (each one a hitch).
        mapOf(
            "RUBY_GC_HEAP_INIT_SLOTS" to "400000",
            "RUBY_GC_HEAP_FREE_SLOTS" to "100000",
            "RUBY_GC_HEAP_GROWTH_FACTOR" to "1.4",
            "RUBY_GC_MALLOC_LIMIT" to "67108864",
            "RUBY_GC_MALLOC_LIMIT_MAX" to "134217728",
            "RUBY_GC_OLDMALLOC_LIMIT" to "67108864",
            "RUBY_GC_OLDMALLOC_LIMIT_MAX" to "268435456",
        ).forEach { (k, v) -> Os.setenv(k, v, true) }
        // System.user_language in the engine (Essentials reads it for its language setting)
        Os.setenv("LANG", java.util.Locale.getDefault().toString().ifBlank { "en_US" } + ".UTF-8", true)

        prepareFullscreenWindow()
        super.onCreate(savedInstanceState)
        if (SDLActivity.mBrokenLibraries) return
        watchdog = MainThreadWatchdog(CrashReports.engineLog(this)).also { it.start() }

        injector = KeyInjector(::onFrontendAction).apply {
            autofire = inputConfig.autofire
            autofireHz = settings.autofireRateHz
        }
        mapper = ControllerMapper(injector, inputConfig, settings.controllerProfile).apply {
            onControllerSeen = { c -> runOnUiThread { onControllerUsed(c.name, c.profile.label) } }
        }
        buildOverlays()
        (getSystemService(INPUT_SERVICE) as InputManager).registerInputDeviceListener(this, Handler(Looper.getMainLooper()))
        usingController = mapper.connected().isNotEmpty()
        applyTouchVisibility()
        hideSystemBars()

        status = EngineStatus(File(repo.runtimeDir, "status-${g.id}.txt")) { m ->
            turboActive = m["turbo"] == "1"
            touch?.turboActive = turboActive
            // Not only while the info overlay is shown
            m["rate"]?.toFloatOrNull()?.let { matchDisplayRate(it) }
            info?.let { v ->
                v.turbo = turboActive
                v.fps = m["fps"]?.toIntOrNull() ?: v.fps
                v.worstMs = m["worst"]?.toIntOrNull() ?: v.worstMs
                if (m.containsKey("fps")) v.engineAlive = true
                v.refresh()
            }
        }.also { it.start() }
    }

    private var matchedRate = 0f

    /**
     * RPG Maker XP runs at 40 fps, which can't be paced evenly on a 60 Hz display
     * (frames alternate between 2 and 1 refreshes: judder). Tell Android the
     * content rate; it then picks a display mode that divides evenly (e.g. 120 Hz)
     * where the device has one. Android 11+.
     */
    private fun matchDisplayRate(rate: Float) {
        if (Build.VERSION.SDK_INT < 30 || rate <= 0f || rate == matchedRate) return
        val surface = SDLActivity.mSurface?.holder?.surface ?: return
        if (!surface.isValid) return
        runCatching {
            surface.setFrameRate(rate, android.view.Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
            matchedRate = rate
        }.onFailure { android.util.Log.w("Yami", "setFrameRate($rate) failed", it) }
    }

    private fun displayAspect(): Float {
        val b = if (Build.VERSION.SDK_INT >= 30) windowManager.maximumWindowMetrics.bounds else null
        val w = b?.width() ?: resources.displayMetrics.widthPixels
        val h = b?.height() ?: resources.displayMetrics.heightPixels
        return maxOf(w, h).toFloat() / minOf(w, h).toFloat()
    }

    private fun buildOverlays() {
        val root = SDLActivity.yamiLayout() ?: return
        val match = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        if (!optimizeMode) {
            touch = TouchControlsView(this, injector, inputConfig.touch, accent).apply {
                opacity = settings.touchOpacity
                haptics = settings.vibration && repo.settings.value.haptics
                onLayoutEdited = { l ->
                    inputConfig = inputConfig.copy(touch = l)
                    InputConfig.save(this@PlayerActivity, inputConfig)
                }
            }
            root.addView(touch, match)
        }
        info = InfoOverlayView(this, accent).apply { showInfo = settings.showInfo && !optimizeMode }
        root.addView(info, match)
        menu = QuickMenuView(this, accent, ::onMenuAction).apply { visibility = View.GONE }
        root.addView(menu, match)
        logView = LogOverlayView(this, accent) { logView?.visibility = View.GONE }.apply { visibility = View.GONE }
        root.addView(logView, match)
    }

    private fun applyTouchVisibility() {
        val t = touch ?: return
        val hide = !settings.showTouchControls || (usingController && inputConfig.touch.hideWithController)
        t.visibility = if (hide && !t.editing) View.GONE else View.VISIBLE
    }

    private fun onControllerUsed(name: String, profile: String) {
        if (!usingController) {
            usingController = true
            applyTouchVisibility()
            Toast.makeText(this, "🎮 $name — $profile", Toast.LENGTH_SHORT).show()
        }
    }

    /**
     * Lay the window out edge-to-edge and hide the bars *before* SDL attaches its
     * SurfaceView. Otherwise the surface starts at the inset size (e.g. 1920x970)
     * and is resized to full screen while the engine is already rendering, which
     * can leave SDL's UI and render threads waiting on each other (frozen screen).
     */
    private fun prepareFullscreenWindow() {
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_FULLSCREEN or
            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= 30) window.setDecorFitsSystemWindows(false)
        if (Build.VERSION.SDK_INT >= 28) window.attributes = window.attributes.apply {
            layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        // Bars are hidden in hideSystemBars() once SDL has installed the decor view;
        // touching the insets controller before that throws on Android 13.
    }

    private fun hideSystemBars() {
        if (window.peekDecorView() == null) return
        if (Build.VERSION.SDK_INT >= 30) {
            window.insetsController?.let {
                it.hide(WindowInsets.Type.systemBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
        }
    }

    // ---------------------------------------------------------------- input
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!::mapper.isInitialized) return super.dispatchKeyEvent(event)
        menu?.takeIf { it.visibility == View.VISIBLE }?.let { m ->
            if (m.handleKey(event)) return true
        }
        if (mapper.onKey(event)) {
            if (!usingController) onControllerUsed(event.device?.name ?: "Controller", mapper.profileFor(event.device).label)
            return true
        }
        if (event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_UP) {
                val lv = logView
                if (lv != null && lv.visibility == View.VISIBLE) lv.visibility = View.GONE else toggleMenu()
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(ev: MotionEvent): Boolean {
        if (::mapper.isInitialized && mapper.onMotion(ev)) return true
        return super.dispatchGenericMotionEvent(ev)
    }

    override fun onInputDeviceAdded(deviceId: Int) {
        usingController = mapper.connected().isNotEmpty(); applyTouchVisibility()
    }
    override fun onInputDeviceRemoved(deviceId: Int) {
        usingController = mapper.connected().isNotEmpty(); injector.releaseAll(); applyTouchVisibility()
    }
    override fun onInputDeviceChanged(deviceId: Int) {}

    private fun onFrontendAction(b: RgssButton, down: Boolean) {
        if (b == RgssButton.MENU && down) runOnUiThread { toggleMenu() }
    }

    // ----------------------------------------------------------------- menu
    private fun toggleMenu() {
        val m = menu ?: return
        if (m.visibility == View.VISIBLE) {
            m.visibility = View.GONE
        } else {
            injector.releaseAll()
            m.show(QuickMenuView.State(
                turbo = turboActive,
                touchVisible = touch?.visibility == View.VISIBLE,
                info = info?.showInfo == true,
                title = game?.title ?: "",
            ))
        }
    }

    private fun onMenuAction(a: QuickMenuView.Action) {
        menu?.visibility = View.GONE
        when (a) {
            QuickMenuView.Action.RESUME -> {}
            QuickMenuView.Action.TURBO -> injector.tap(RgssButton.TURBO)
            QuickMenuView.Action.TOUCH -> touch?.let {
                settings = settings.copy(showTouchControls = it.visibility != View.VISIBLE)
                applyTouchVisibility()
            }
            QuickMenuView.Action.EDIT_LAYOUT -> touch?.let { it.editing = !it.editing; it.visibility = View.VISIBLE }
            QuickMenuView.Action.RESET_LAYOUT -> touch?.resetLayout()
            QuickMenuView.Action.INFO -> info?.let { it.showInfo = !it.showInfo; it.refresh() }
            QuickMenuView.Action.SCREENSHOT -> screenshot()
            QuickMenuView.Action.LOG -> logView?.let { it.visibility = View.VISIBLE; it.refresh() }
            QuickMenuView.Action.SOFT_RESET -> injector.tap(RgssButton.RESET)
            QuickMenuView.Action.RESTART -> restart()
            QuickMenuView.Action.QUIT -> quitToLibrary()
        }
    }

    private fun screenshot() {
        val surface = SDLActivity.yamiSurface() ?: return
        if (surface.width == 0) return
        val bmp = Bitmap.createBitmap(surface.width, surface.height, Bitmap.Config.ARGB_8888)
        PixelCopy.request(surface, bmp, { result ->
            if (result != PixelCopy.SUCCESS) return@request
            runCatching {
                val name = "${game?.title ?: "Yami"}_${System.currentTimeMillis()}.png".replace(Regex("[^\\w.\\- ]"), "_")
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Yami")
                }
                contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)?.let { uri ->
                    contentResolver.openOutputStream(uri)?.use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                }
                runOnUiThread { Toast.makeText(this, "Screenshot saved to Pictures/Yami", Toast.LENGTH_SHORT).show() }
            }
        }, Handler(Looper.getMainLooper()))
    }

    /** Closes the engine and starts it again in a fresh process. */
    private fun restart() {
        val id = game?.id ?: return
        recordSession()
        CrashReports.endSession(this)
        startActivity(Intent(this, MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_RELAUNCH, id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        hardExit()
    }

    private fun quitToLibrary() {
        recordSession()
        CrashReports.endSession(this)
        runCatching { SDLActivity.nativeSendQuit() }
        // Give RGSS a moment to unwind cleanly, then make sure the process is gone.
        Handler(Looper.getMainLooper()).postDelayed({ hardExit() }, 1500)
    }

    private fun hardExit() {
        finishAndRemoveTask()
        Handler(Looper.getMainLooper()).postDelayed({ exitProcess(0) }, 150)
    }

    // ------------------------------------------------------------ lifecycle
    override fun onResume() {
        super.onResume()
        resumedAt = SystemClock.elapsedRealtime()
        hideSystemBars()
        matchedRate = 0f // the surface may have been recreated; re-apply on the next status update
    }

    override fun onPause() {
        recordSession()
        if (::injector.isInitialized) injector.releaseAll()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    private fun recordSession() {
        val g = game ?: return
        if (resumedAt == 0L || optimizeMode) return
        val secs = (SystemClock.elapsedRealtime() - resumedAt) / 1000
        resumedAt = SystemClock.elapsedRealtime()
        if (secs > 0) runCatching { repo.writeStats(g.id, secs) }
    }

    override fun onDestroy() {
        recordSession()
        // Reached on a normal exit (game called exit, or we finished); a crash never gets here.
        if (isFinishing) CrashReports.endSession(this)
        status?.stop()
        watchdog?.stop()
        runCatching { (getSystemService(INPUT_SERVICE) as InputManager).unregisterInputDeviceListener(this) }
        super.onDestroy()
        // Native state (Ruby VM, GL context, statics) can't be reused: always start clean.
        Handler(Looper.getMainLooper()).postDelayed({ exitProcess(0) }, 200)
    }
}
