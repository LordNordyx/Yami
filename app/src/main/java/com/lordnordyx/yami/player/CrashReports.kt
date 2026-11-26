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
    fun nativeCrash(ctx: Context) = File(dir(ctx), "native-crash.txt")
    private fun javaCrash(ctx: Context) = File(dir(ctx), "java-crash.txt")
    private fun marker(ctx: Context) = File(dir(ctx), "session-running")
    fun lastReport(ctx: Context) = File(dir(ctx), "last-crash-report.txt")

    // ------------------------------------------------------- engine process
    /** Call in the engine process before the native library loads. */
    fun beginSession(ctx: Context, gameId: String, title: String) {
        nativeCrash(ctx).delete()
        javaCrash(ctx).delete()
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

        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            runCatching { javaCrash(ctx).writeText("Thread: ${t.name}\n${e.stackTraceToString()}") }
            previous?.uncaughtException(t, e)
        }
    }

    /** The game ended normally (quit, exit from the game, finish). */
    fun endSession(ctx: Context) {
        marker(ctx).delete()
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
        val (gameId, title, started) = (m.readLines() + listOf("", "", "0")).let { Triple(it[0], it[1], it[2].toLongOrNull() ?: 0) }
        m.delete()

        val native = nativeCrash(ctx).takeIf { it.exists() && it.length() > 0 }?.readText()
        val java = javaCrash(ctx).takeIf { it.exists() }?.readText()
        val engine = engineLog(ctx).takeIf { it.exists() }?.readLines()?.takeLast(150)?.joinToString("\n")
        val logcat = readLogcat()

        val evidence = native != null || java != null ||
            logcat.contains("Fatal signal") || logcat.contains("FATAL EXCEPTION") ||
            logcat.contains("yami-crash") || (engine?.contains("Error", ignoreCase = false) == true)
        if (!evidence) return null

        val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        val report = buildString {
            appendLine("Yami crash report")
            appendLine("App ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · ${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) · ${Build.SUPPORTED_ABIS.joinToString()}")
            appendLine("Game: $title [$gameId] · started ${fmt.format(Date(started))}")
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
        nativeCrash(ctx).takeIf { it.exists() && it.length() > 0 }?.let { appendLine("\n== Native crash =="); appendLine(it.readText().trim()) }
        appendLine("\n== Engine output ==")
        appendLine(engineLog(ctx).takeIf { it.exists() }?.readLines()?.takeLast(300)?.joinToString("\n")?.ifBlank { null } ?: "(empty)")
        appendLine("\n== System log ==")
        appendLine(readLogcat().trim())
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
