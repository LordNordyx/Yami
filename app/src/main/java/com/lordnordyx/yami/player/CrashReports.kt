package com.lordnordyx.yami.player

import android.content.Context
import android.os.Build
import android.system.Os
import android.system.OsConstants
import com.lordnordyx.yami.BuildConfig
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Crash reporting across the two processes:
 *  - the engine process marks a session as running, sends native stdout/stderr
 *    to engine.log, and the engine's signal handler writes native-crash.txt;
 *  - when the library comes back and the session never ended cleanly, it
 *    collects those files plus the app's own logcat into one report.
 */
object CrashReports {

    private fun dir(ctx: Context) = File(ctx.filesDir, "logs").apply { mkdirs() }
    fun engineLog(ctx: Context) = File(dir(ctx), "engine.log")
    private fun previousLog(ctx: Context) = File(dir(ctx), "engine-previous.log")
    fun nativeCrash(ctx: Context) = File(dir(ctx), "native-crash.txt")
    private fun javaCrash(ctx: Context) = File(dir(ctx), "java-crash.txt")
    private fun marker(ctx: Context) = File(dir(ctx), "session-running")
    private fun selfExit(ctx: Context) = File(dir(ctx), "self-exit")

    /** The game's own scripts ended the session (not the player): report it like a crash. */
    fun markSelfExit(ctx: Context) {
        runCatching { selfExit(ctx).writeText("1") }
    }
    fun lastReport(ctx: Context) = File(dir(ctx), "last-crash-report.txt")

    // ------------------------------------------------------- engine process
    /** Call in the engine process before the native library loads. */
    fun beginSession(ctx: Context, gameId: String, title: String) {
        nativeCrash(ctx).delete()
        javaCrash(ctx).delete()
        // keep the last run's output: it's usually the one being asked about
        runCatching { engineLog(ctx).takeIf { it.length() > 0 }?.let { it.copyTo(previousLog(ctx), overwrite = true) } }
        marker(ctx).writeText("$gameId\n$title\n${System.currentTimeMillis()}\n")
        runCatching {
            // Ruby errors, mkxp-z messages and our runtime's prints go to stdout/stderr,
            // which Android otherwise discards.
            val fd = Os.open(engineLog(ctx).absolutePath,
                OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_TRUNC, 420 /* 0644 */)
            Os.dup2(fd, 1)
            Os.dup2(fd, 2)
        }
        Os.setenv("YAMI_CRASH_FILE", nativeCrash(ctx).absolutePath, true)
        // the runtime writes the reason here the moment the game's scripts end
        selfExit(ctx).delete()
        Os.setenv("YAMI_SELF_EXIT_FILE", selfExit(ctx).absolutePath, true)

        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            runCatching { javaCrash(ctx).writeText("Thread: ${t.name}\n${e.stackTraceToString()}") }
            previous?.uncaughtException(t, e)
        }
    }

    /** The game ended normally (quit, exit from the game, finish). */
    fun endSession(ctx: Context) {
        marker(ctx).delete()
        selfExit(ctx).delete()
    }

    // ------------------------------------------------------ library process
    /**
     * Returns a report if the last session crashed. A session that was merely
     * swiped away also leaves the marker, so we only report when there is
     * evidence of a crash.
     */
    fun collect(ctx: Context): String? {
        val m = marker(ctx)
        if (!m.exists()) return null
        // The library comes back ~0.5 s before the engine process has finished
        // shutting down: give a self-exit note or crash file a moment to appear.
        val until = System.currentTimeMillis() + 2500
        while (System.currentTimeMillis() < until && m.exists() &&
            !selfExit(ctx).exists() && !nativeCrash(ctx).exists() && !javaCrash(ctx).exists()) Thread.sleep(100)
        if (!m.exists()) return null      // the player quit: endSession removed it
        val (gameId, title, started) = (m.readLines() + listOf("", "", "0")).let { Triple(it[0], it[1], it[2].toLongOrNull() ?: 0) }
        m.delete()

        val native = nativeCrash(ctx).takeIf { it.exists() && it.length() > 0 }?.readText()
        val java = javaCrash(ctx).takeIf { it.exists() }?.readText()
        val engine = engineLog(ctx).takeIf { it.exists() }?.readLines()?.let(::quiet)?.takeLast(150)?.joinToString("\n")
        val logcat = readLogcat()
        val exit = engineExit(ctx, started)
        val selfNote = selfExit(ctx).takeIf { it.exists() }?.readText()?.trim()
        val closedItself = selfNote != null
        selfExit(ctx).delete()
        val why = engineLog(ctx).takeIf { it.exists() }?.readLines()
            ?.filter { l -> listOf("game scripts ended", "game called", "game asked to start", "unsupported Windows call").any { l.contains(it) } }
            ?.takeLast(12)?.joinToString("\n")

        val evidence = closedItself || native != null || java != null || exit?.second == true ||
            logcat.contains("Fatal signal") || logcat.contains("FATAL EXCEPTION") ||
            logcat.contains("yami-crash") || (engine?.contains("Error", ignoreCase = false) == true)
        if (!evidence) return null

        val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        val report = buildString {
            appendLine(if (closedItself && native == null && java == null) "$title closed itself" else "Yami crash report")
            appendLine("App ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · ${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) · ${Build.SUPPORTED_ABIS.joinToString()}")
            appendLine("Game: $title [$gameId] · started ${fmt.format(Date(started))}")
            selfNote?.takeIf { it.isNotBlank() && it != "1" }?.let { appendLine("\nHow it ended: $it") }
            why?.takeIf { it.isNotBlank() }?.let { appendLine("\n== What the game did =="); appendLine(it) }
            exit?.let { appendLine("\n== Why the game stopped (Android) =="); appendLine(it.first) }
            native?.let { appendLine("\n== Native crash =="); appendLine(it.trim()) }
            java?.let { appendLine("\n== Java exception =="); appendLine(it.trim()) }
            engine?.takeIf { it.isNotBlank() }?.let { appendLine("\n== Engine output (last lines) =="); appendLine(it.trim()) }
            appendLine("\n== System log =="); appendLine(logcat.trim())
        }
        lastReport(ctx).writeText(report)
        return report
    }

    /** Current engine output + system log, for problems that aren't crashes (hangs, black screen). */
    fun sessionLog(ctx: Context): String = buildString {
        appendLine("Yami session log")
        appendLine("App ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · ${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        marker(ctx).takeIf { it.exists() }?.readLines()?.getOrNull(1)?.let { appendLine("Game: $it") }
        engineExit(ctx, 0)?.let { appendLine("\n== Last time the game stopped (Android) =="); appendLine(it.first) }
        nativeCrash(ctx).takeIf { it.exists() && it.length() > 0 }?.let { appendLine("\n== Native crash =="); appendLine(it.readText().trim()) }
        previousLog(ctx).takeIf { it.exists() }?.readLines()?.let(::quiet)?.takeLast(60)?.joinToString("\n")?.takeIf { it.isNotBlank() }?.let {
            appendLine("\n== Previous run (last lines) ==")
            appendLine(it)
        }
        appendLine("\n== Engine output ==")
        appendLine(engineLog(ctx).takeIf { it.exists() }?.readLines()?.let(::quiet)?.takeLast(200)?.joinToString("\n")?.ifBlank { null } ?: "(empty)")
        appendLine("\n== System log ==")
        appendLine(readLogcat().trim())
    }

    /** Without Ruby's harmless redefinition warnings, which bury everything else. */
    private val noise = Regex("warning: (already initialized constant|previous definition of|key .* is duplicated)")
    private fun quiet(lines: List<String>) = lines.filterNot { noise.containsMatchIn(it) }

    /**
     * Android's own record of how the engine process ended (API 30+): low
     * memory, a signal, killed... Catches the deaths that leave no crash file.
     * @return the description, and whether it was abnormal.
     */
    private fun engineExit(ctx: Context, since: Long): Pair<String, Boolean>? {
        if (Build.VERSION.SDK_INT < 30) return null
        return runCatching {
            val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val e = am.getHistoricalProcessExitReasons(ctx.packageName, 0, 10)
                .firstOrNull { it.processName.endsWith(":engine") && it.timestamp >= since } ?: return null
            val R = android.app.ApplicationExitInfo::class.java
            val name = R.fields.firstOrNull { f -> f.name.startsWith("REASON_") && runCatching { f.getInt(null) == e.reason }.getOrDefault(false) }
                ?.name?.removePrefix("REASON_")?.lowercase()?.replace('_', ' ') ?: "reason ${e.reason}"
            val fmt = SimpleDateFormat("HH:mm:ss", Locale.US)
            val abnormal = e.reason !in setOf(android.app.ApplicationExitInfo.REASON_EXIT_SELF,
                android.app.ApplicationExitInfo.REASON_USER_REQUESTED, android.app.ApplicationExitInfo.REASON_USER_STOPPED)
            val text = buildString {
                append("$name at ${fmt.format(Date(e.timestamp))}")
                if (e.status != 0) append(" · status/signal ${e.status}")
                e.description?.takeIf { it.isNotBlank() }?.let { append(" · $it") }
                append(" · memory ${e.pss / 1024} MB (PSS), ${e.rss / 1024} MB (RSS)")
                append(" · importance ${e.importance}")
            }
            text to abnormal
        }.getOrNull()
    }

    /** Apps may read their own log lines; both of Yami's processes share a uid. */
    private fun readLogcat(): String = runCatching {
        val p = ProcessBuilder("logcat", "-d", "-v", "time", "-t", "600").redirectErrorStream(true).start()
        val lines = p.inputStream.bufferedReader().readLines()
        p.destroy()
        val interesting = Regex("yami|SDL|mkxp|libc|DEBUG|AndroidRuntime|openal|crash|Fatal|FATAL|art |GL|EGL|Adreno|BLASTBufferQueue", RegexOption.IGNORE_CASE)
        lines.filter { interesting.containsMatchIn(it) }.takeLast(250).joinToString("\n")
    }.getOrDefault("(logcat unavailable)")
}
