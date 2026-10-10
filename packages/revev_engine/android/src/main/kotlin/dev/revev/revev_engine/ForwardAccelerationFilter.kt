package dev.revev.revev_engine

import kotlin.math.abs
import kotlin.math.exp

/** Input is already projected onto the vehicle-forward horizontal axis. */
class ForwardAccelerationFilter {
    private var value = 0.0
    fun reset() { value = 0.0 }

    fun update(raw: Double, dt: Double): Double {
        if (!raw.isFinite() || !dt.isFinite() || dt <= 0.0) return value
        val input = if (abs(raw) < .08) 0.0 else raw.coerceIn(-12.0, 12.0)
        // Fast attack AND release/sign reversal during a manoeuvre. Keep the
        // longer vibration filter near zero. No extra speed smoothing follows.
        val tau = if (maxOf(abs(input), abs(value)) >= .35) .03 else .12
        value += (input-value)*(1-exp(-dt.coerceAtMost(.1)/tau))
        return value
    }
}
