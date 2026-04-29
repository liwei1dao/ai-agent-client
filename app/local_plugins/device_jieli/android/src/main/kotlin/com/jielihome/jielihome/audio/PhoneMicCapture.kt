package com.jielihome.jielihome.audio

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * 手机麦克风采集，输出 16kHz / 16bit / mono PCM。
 * 每 20ms 切一帧（320 samples = 640 bytes）。
 *
 * 用法：
 *   val mic = PhoneMicCapture(context) { pcm -> /* push to bridge */ }
 *   mic.start()
 *   ...
 *   mic.stop()
 */
class PhoneMicCapture(
    private val context: Context,
    private val sampleRate: Int = 16000,
    private val frameDurationMs: Int = 20,
    private val onFrame: (pcm: ByteArray) -> Unit,
    private val onError: (code: Int, msg: String) -> Unit = { _, _ -> },
) {
    private val running = AtomicBoolean(false)
    private var recorder: AudioRecord? = null
    private var worker: Thread? = null

    val frameSizeBytes: Int = sampleRate * frameDurationMs / 1000 * 2 /* 16bit */

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        if (running.get()) return true
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "RECORD_AUDIO permission missing")
            onError(-101, "RECORD_AUDIO permission missing")
            return false
        }

        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufSize = maxOf(minBuf, frameSizeBytes * 4)

        val ar = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufSize
        )
        if (ar.state != AudioRecord.STATE_INITIALIZED) {
            ar.release()
            Log.w(TAG, "AudioRecord init failed")
            onError(-102, "AudioRecord init failed (state=${ar.state})")
            return false
        }
        recorder = ar
        running.set(true)
        ar.startRecording()

        worker = thread(name = "device-jieli-mic", isDaemon = true) {
            val frame = ByteArray(frameSizeBytes)
            while (running.get()) {
                val n = try { ar.read(frame, 0, frameSizeBytes) } catch (t: Throwable) {
                    onError(-103, "AudioRecord.read crashed: ${t.message}"); -1
                }
                when {
                    n < 0 -> { onError(-104, "AudioRecord.read err code=$n"); break }
                    n == 0 -> continue
                    n == frameSizeBytes -> onFrame(frame.copyOf())
                    else -> onFrame(frame.copyOf(n))
                }
            }
        }
        return true
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        recorder = null
        worker?.join(200)
        worker = null
    }

    companion object {
        private const val TAG = "PhoneMicCapture"
    }
}
