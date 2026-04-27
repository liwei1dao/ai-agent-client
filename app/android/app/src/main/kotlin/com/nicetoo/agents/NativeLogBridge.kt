package com.nicetoo.agents

import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.atomic.AtomicBoolean

/**
 * EventChannel (`ai_agent_client/log/native`) producer.
 *
 * Tails `logcat` filtered by current PID and pushes every line to Dart as a map:
 *   { source: "android", tag: <tag>, level: <v|d|i|w|e|a>, message: <msg>, time: <hh:mm:ss.mmm> }
 *
 * Requires no special permission on Android 8+ when filtered by own PID.
 */
class NativeLogBridge : EventChannel.StreamHandler {
    companion object {
        const val CHANNEL = "ai_agent_client/log/native"
        // logcat -v threadtime line example:
        //   01-02 03:04:05.678  1234  1234 I TAG     : message...
        private val LINE_REGEX = Regex(
            """^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\s+\d+\s+\d+\s+([VDIWEAF])\s+([^:]+?)\s*:\s(.*)$"""
        )
    }

    @Volatile private var sink: EventChannel.EventSink? = null
    private val running = AtomicBoolean(false)
    private var process: java.lang.Process? = null
    private var thread: Thread? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        start()
    }

    override fun onCancel(arguments: Any?) {
        stop()
        sink = null
    }

    private fun start() {
        if (running.getAndSet(true)) return
        val pid = android.os.Process.myPid().toString()
        thread = Thread({
            try {
                // Clear logcat then tail. `-v threadtime` for parseable format.
                val proc = ProcessBuilder(
                    "logcat",
                    "--pid=$pid",
                    "-v",
                    "threadtime",
                    "*:V",
                )
                    .redirectErrorStream(true)
                    .start()
                process = proc
                val reader = BufferedReader(InputStreamReader(proc.inputStream))
                while (running.get()) {
                    val line = reader.readLine() ?: break
                    dispatch(line)
                }
            } catch (t: Throwable) {
                sink?.error("logcat_failed", t.message, null)
            }
        }, "native-log-bridge").apply {
            isDaemon = true
            start()
        }
    }

    private fun stop() {
        running.set(false)
        try { process?.destroy() } catch (_: Throwable) {}
        process = null
        thread = null
    }

    private fun dispatch(line: String) {
        val m = LINE_REGEX.matchEntire(line)
        val payload: Map<String, Any?> = if (m != null) {
            val (time, level, tag, msg) = m.destructured
            val trimmedTag = tag.trim()
            // Flutter 引擎 stdout/stderr 在 Android 上以 tag=flutter 进 logcat；
            // Talker 开 useConsoleLogs 时每条 Dart 日志都会打到 stdout，若再回灌就形成无限循环。
            if (trimmedTag == "flutter") return
            mapOf(
                "source" to "android",
                "time" to time,
                "level" to level.lowercase(),
                "tag" to trimmedTag,
                "message" to msg,
            )
        } else {
            mapOf(
                "source" to "android",
                "level" to "i",
                "message" to line,
            )
        }
        val s = sink ?: return
        // EventSink.success must be called on main thread
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try { s.success(payload) } catch (_: Throwable) {}
        }
    }
}
