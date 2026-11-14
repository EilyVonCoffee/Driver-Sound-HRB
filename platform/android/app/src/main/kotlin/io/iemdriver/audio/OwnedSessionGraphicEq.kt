package io.iemdriver.audio

import android.media.audiofx.DynamicsProcessing

/**
 * Optional Android framework graphic EQ for a session owned by this app.
 * Pass only the session ID returned by this app's own AudioTrack/MediaPlayer.
 * This API has fixed-width graphic bands, not the PEQ/Q controls in the C++ core.
 */
class OwnedSessionGraphicEq(
    sessionId: Int,
    private val channelCount: Int = 2,
) : AutoCloseable {
    private val effect: DynamicsProcessing

    init {
        require(sessionId > 0) { "Use a valid session ID from this app's own player or track" }
        require(channelCount in 1..2) { "Only mono and stereo sessions are supported here" }

        val config = DynamicsProcessing.Config.Builder(
            DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
            channelCount,
            false, 0, // pre-EQ
            false, 0, // multiband compressor
            true, 10, // post-EQ graphic stage
            false,    // limiter
        ).build()
        effect = DynamicsProcessing(0, sessionId, config).apply { enabled = true }
    }

    /**
     * Applies Android's fixed-width graphic bands. Cutoffs must be strictly
     * increasing; this cannot represent arbitrary PEQ center frequency or Q.
     */
    fun setGraphicBands(cutoffHz: FloatArray, gainDb: FloatArray) {
        require(cutoffHz.size == 10 && gainDb.size == 10)
        require(cutoffHz.all { it in 20f..20_000f })
        require((1 until cutoffHz.size).all { cutoffHz[it] > cutoffHz[it - 1] })
        require(gainDb.all { it in -24f..12f })

        repeat(channelCount) { channel ->
            repeat(10) { index ->
                val band = effect.getPostEqBandByChannelIndex(channel, index)
                band.setEnabled(true)
                band.setCutoffFrequency(cutoffHz[index])
                band.setGain(gainDb[index])
                effect.setPostEqBandByChannelIndex(channel, index, band)
            }
        }
    }

    override fun close() {
        effect.enabled = false
        effect.release()
    }
}
