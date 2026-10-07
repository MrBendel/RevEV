package dev.revev.revev_engine

import android.media.AudioManager
import kotlin.test.Test
import kotlin.test.assertEquals

class AudioFocusPolicyTest {
    @Test fun interruptionsRestoreGainWithoutRestartingAndIgnoreOldCallbacks() {
        var gain = 1f
        var stops = 0
        val policy = AudioFocusPolicy({ gain = it }, { ++stops })
        val first = policy.begin()
        repeat(20) {
            policy.changed(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK, first)
            assertEquals(.2f, gain)
            policy.changed(AudioManager.AUDIOFOCUS_GAIN, first)
            assertEquals(1f, gain)
            policy.changed(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, first)
            assertEquals(0f, gain)
            policy.changed(AudioManager.AUDIOFOCUS_GAIN, first)
            assertEquals(1f, gain)
        }
        assertEquals(0, stops)
        policy.end()
        val second = policy.begin()
        policy.changed(AudioManager.AUDIOFOCUS_LOSS, first)
        assertEquals(0, stops)
        policy.changed(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, second)
        policy.changed(AudioManager.AUDIOFOCUS_GAIN, first)
        assertEquals(0f, gain)
        policy.changed(AudioManager.AUDIOFOCUS_LOSS, second)
        assertEquals(1, stops)
        policy.changed(AudioManager.AUDIOFOCUS_GAIN, second)
        assertEquals(0f, gain)
    }
}
