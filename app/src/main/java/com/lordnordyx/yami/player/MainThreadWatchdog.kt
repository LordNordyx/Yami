package com.lordnordyx.yami.player

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.io.File

/**
 * Detects a frozen UI thread in the engine process and writes every thread's
 * stack to the engine log, so a hang (black screen) shows what it's stuck on.
 */
class MainThreadWatchdog(private val log: File, private val stallMs: Long = 4000) {
    @Volatile private var lastPong = SystemClock.elapsedRealtime()
    @Volatile private var running = true
    private val main = Handler(Looper.getMainLooper())

    fun start() {
        Thread({
            var reported = false
            while (running) {
                main.post { lastPong = SystemClock.elapsedRealtime() }
                Thread.sleep(1000)
                val stalled = SystemClock.elapsedRealtime() - lastPong
                if (stalled > stallMs && !reported) {
                    reported = true
                    dump("UI thread unresponsive for ${stalled} ms")
                } else if (stalled < stallMs && reported) {
                    reported = false
                    append("[yami-watchdog] UI thread recovered\n")
                }
            }
        }, "yami-watchdog").apply { isDaemon = true }.start()
    }

    fun stop() { running = false }

    private fun dump(reason: String) {
        val sb = StringBuilder("\n[yami-watchdog] $reason — thread stacks:\n")
        val all = Thread.getAllStackTraces()
        val ordered = all.entries.sortedBy { if (it.key == Looper.getMainLooper().thread) 0 else 1 }
        for ((t, st) in ordered) {
            if (st.isEmpty()) continue
            sb.append("  \"${t.name}\" ${t.state}\n")
            st.take(25).forEach { sb.append("      at $it\n") }
        }
        append(sb.toString())
    }

    @Synchronized
    private fun append(s: String) {
        runCatching { log.appendText(s) }
        android.util.Log.w("yami-watchdog", s)
    }
}
