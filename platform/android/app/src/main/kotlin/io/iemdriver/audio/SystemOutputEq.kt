package io.iemdriver.audio

import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import kotlin.math.abs

data class SystemEqBand(
    val enabled: Boolean,
    val frequencyHz: Float,
    val gainDb: Float,
)

data class SystemEqStatus(
    val backend: String,
    val available: Boolean,
    val message: String,
)

/** Best-effort global-output EQ. OEMs may refuse effects attached to session 0. */
class SystemOutputEq : AutoCloseable {
    private var dynamics: DynamicsProcessing? = null
    private var legacy: Equalizer? = null
    private var currentStatus = SystemEqStatus(
        backend = "unsupported",
        available = false,
        message = "System output effects have not been initialized",
    )

    val status: SystemEqStatus get() = currentStatus

    fun apply(bands: List<SystemEqBand>): SystemEqStatus {
        require(bands.size == 10) { "Exactly 10 EQ bands are required" }
        require(bands.all {
            it.frequencyHz.isFinite() && it.frequencyHz in 20f..20_000f &&
                it.gainDb.isFinite() && it.gainDb in -24f..12f
        }) { "EQ parameters are outside supported limits" }

        val dynamicsEffect = dynamics ?: runCatching { createDynamics() }
            .onFailure { releaseDynamics() }
            .getOrNull()
        if (dynamicsEffect != null && runCatching {
                applyDynamics(dynamicsEffect, bands)
            }.getOrDefault(false)
        ) {
            currentStatus = SystemEqStatus(
                backend = "dynamicsProcessing",
                available = true,
                message = "Best-effort global graphic EQ; Q, filter shape and preamp are not supported",
            )
            return currentStatus
        }
        releaseDynamics()

        val equalizer = legacy ?: runCatching { createLegacy() }
            .onFailure { releaseLegacy() }
            .getOrNull()
        if (equalizer != null && runCatching {
                applyLegacy(equalizer, bands)
            }.getOrDefault(false)
        ) {
            currentStatus = SystemEqStatus(
                backend = "legacyEqualizer",
                available = true,
                message = "Best-effort global graphic EQ; PEQ Q, filter shape and preamp are not supported",
            )
            return currentStatus
        }
        releaseLegacy()
        currentStatus = SystemEqStatus(
            backend = "unsupported",
            available = false,
            message = "This Android ROM did not grant control of a global output effect",
        )
        return currentStatus
    }

    private fun createDynamics(): DynamicsProcessing {
        val config = DynamicsProcessing.Config.Builder(
            DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
            2,
            false, 0,
            false, 0,
            true, 10,
            false,
        ).build()
        return DynamicsProcessing(0, 0, config).also { effect ->
            check(effect.hasControl()) { "Global DynamicsProcessing has no control" }
            dynamics = effect
        }
    }

    private fun createLegacy(): Equalizer = Equalizer(0, 0).also { effect ->
        check(effect.hasControl()) { "Global Equalizer has no control" }
        legacy = effect
    }

    private fun applyDynamics(
        effect: DynamicsProcessing,
        bands: List<SystemEqBand>,
    ): Boolean {
        if (!effect.hasControl()) return false
        val ordered = bands.sortedBy { it.frequencyHz }
        val cutoffs = FloatArray(ordered.size)
        var previous = 19f
        for (index in ordered.indices) {
            val minimum = previous + 1f
            val maximum = 20_000f - (ordered.size - index - 1)
            cutoffs[index] = ordered[index].frequencyHz.coerceIn(minimum, maximum)
            previous = cutoffs[index]
        }
        repeat(2) { channel ->
            repeat(ordered.size) { index ->
                val band = effect.getPostEqBandByChannelIndex(channel, index)
                band.setEnabled(ordered[index].enabled)
                band.setCutoffFrequency(cutoffs[index])
                band.setGain(if (ordered[index].enabled) ordered[index].gainDb else 0f)
                effect.setPostEqBandByChannelIndex(channel, index, band)
            }
        }
        effect.enabled = true
        return effect.enabled && effect.hasControl()
    }

    private fun applyLegacy(
        effect: Equalizer,
        bands: List<SystemEqBand>,
    ): Boolean {
        if (!effect.hasControl()) return false
        val range = effect.bandLevelRange
        val minimum = range.getOrNull(0)?.toInt() ?: return false
        val maximum = range.getOrNull(1)?.toInt() ?: return false
        repeat(effect.numberOfBands.toInt()) { index ->
            val centerHz = effect.getCenterFreq(index.toShort()) / 1000f
            val nearest = bands.minByOrNull { abs(it.frequencyHz - centerHz) }
            val gain = if (nearest?.enabled == true) nearest.gainDb else 0f
            val levelMillibels = (gain * 100).toInt().coerceIn(minimum, maximum)
            effect.setBandLevel(index.toShort(), levelMillibels.toShort())
        }
        effect.enabled = true
        return effect.enabled && effect.hasControl()
    }

    private fun releaseDynamics() {
        dynamics?.let { effect ->
            runCatching { effect.enabled = false }
            runCatching { effect.release() }
        }
        dynamics = null
    }

    private fun releaseLegacy() {
        legacy?.let { effect ->
            runCatching { effect.enabled = false }
            runCatching { effect.release() }
        }
        legacy = null
    }

    override fun close() {
        releaseDynamics()
        releaseLegacy()
        currentStatus = SystemEqStatus(
            backend = "unsupported",
            available = false,
            message = "System output EQ is inactive",
        )
    }
}
