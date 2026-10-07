package dev.revev.revev_engine

import android.media.AudioManager

/** Temporary focus loss changes output gain, never engine/session lifetime. */
internal class AudioFocusPolicy(
    private val setGain: (Float) -> Unit,
    private val stopPlayback: () -> Unit,
) {
    private var generation = 0L
    private var active = false

    fun begin(): Long {
        active = true
        setGain(1f)
        return ++generation
    }

    fun end() {
        active = false
        ++generation
        setGain(1f)
    }

    fun changed(change: Int, token: Long) {
        if (!active || token != generation) return
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> setGain(1f)
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> setGain(0f)
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> setGain(0.2f)
            AudioManager.AUDIOFOCUS_LOSS -> {
                active = false
                stopPlayback()
            }
        }
    }
}
