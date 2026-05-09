package com.jielihome.jielihome.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 本地 PCM 播放（A2DP 路径）。用于音视频翻译模式：TTS 不回耳机，直接走 A2DP。
 */
class LocalPlayer(
    private val sampleRate: Int = 16000,
    private val channels: Int = 1,
) {
    private var track: AudioTrack? = null
    private val playing = AtomicBoolean(false)

    fun start() {
        if (playing.get()) return
        val cfg = if (channels == 2) AudioFormat.CHANNEL_OUT_STEREO else AudioFormat.CHANNEL_OUT_MONO
        val minBuf = AudioTrack.getMinBufferSize(sampleRate, cfg, AudioFormat.ENCODING_PCM_16BIT)

        track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(cfg)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(minBuf, sampleRate * 2 * channels)) // 1s
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track?.play()
        playing.set(true)
    }

    fun feed(pcm: ByteArray) {
        if (!playing.get()) return
        runCatching { track?.write(pcm, 0, pcm.size) }
    }

    fun stop() {
        if (!playing.compareAndSet(true, false)) return
        runCatching { track?.stop() }
        runCatching { track?.release() }
        track = null
    }

    @Suppress("unused")
    fun setVolumeFollowingSystemMedia() {
        // hint: 用 AudioManager.STREAM_MUSIC 已由 USAGE_MEDIA 隐式选择
        @Suppress("DEPRECATION")
        AudioManager.STREAM_MUSIC // no-op
    }
}
