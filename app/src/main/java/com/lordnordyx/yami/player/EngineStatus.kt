package com.lordnordyx.yami.player

import android.os.Handler
import android.os.Looper
import java.io.File

/** Polls the small key=value status file the Ruby runtime writes (fps, turbo…). */
class EngineStatus(private val file: File, private val onUpdate: (Map<String, String>) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private var lastModified = 0L
    private val tick = object : Runnable {
        override fun run() {
            val m = file.lastModified()
            if (m != lastModified) {
                lastModified = m
                val map = runCatching {
                    file.readLines().filter { '=' in it }.associate { it.substringBefore('=') to it.substringAfter('=') }
                }.getOrNull()
                if (map != null) onUpdate(map)
            }
            handler.postDelayed(this, 400)
        }
    }
    fun start() { file.delete(); handler.post(tick) }
    fun stop() = handler.removeCallbacks(tick)
}
