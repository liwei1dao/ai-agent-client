package com.jielihome.jielihome.audio

object PcmKit {
    /**
     * 把 16bit 立体声 PCM 拆为左/右两路单声道。
     * 入参字节流：L0_lo L0_hi R0_lo R0_hi L1_lo L1_hi R1_lo R1_hi ...
     * 返回：Pair(leftMono, rightMono)
     */
    fun splitStereo16(pcm: ByteArray): Pair<ByteArray, ByteArray> {
        val frames = pcm.size / 4
        val left = ByteArray(frames * 2)
        val right = ByteArray(frames * 2)
        var li = 0
        var ri = 0
        var i = 0
        while (i + 3 < pcm.size) {
            left[li++] = pcm[i]
            left[li++] = pcm[i + 1]
            right[ri++] = pcm[i + 2]
            right[ri++] = pcm[i + 3]
            i += 4
        }
        return left to right
    }
}
