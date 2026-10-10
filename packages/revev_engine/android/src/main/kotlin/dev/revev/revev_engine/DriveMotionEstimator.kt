package dev.revev.revev_engine

import kotlin.math.abs
import kotlin.math.exp

/** Two-state (speed, forward accelerometer bias) Kalman estimator.
 * Input acceleration is already gravity/mount corrected and low-pass filtered.
 * GPS observes historical speed using a short integral history; corrections are
 * used as a bounded drift correction. Fresh IMU motion owns the fast response.
 */
class DriveMotionEstimator {
    var speedMps = 0.0; private set
    var gpsSpeedMps: Double? = null; private set
    var gpsTime: Double? = null; private set
    var sensorTime: Double? = null; private set
    var sensorAccel = 0.0; private set
    var gpsAccel = 0.0; private set
    var rejectedFixes = 0; private set
    var accelBias = 0.0; private set
    private var velocity = 0.0
    // Covariance entries: speed variance, speed/bias covariance, bias variance.
    private var pVV = 1.0
    private var pVB = 0.0
    private var pBB = .25
    private var lastStep: Double? = null
    private var firstStep: Double? = null
    private data class Integral(val time: Double, val delta: Double, val active: Double)
    private val history = java.util.ArrayDeque<Integral>()
    private var delta = 0.0
    private var active = 0.0

    fun reset() {
        speedMps = 0.0; velocity = 0.0; accelBias = 0.0
        gpsSpeedMps = null; gpsTime = null; sensorTime = null
        sensorAccel = 0.0; gpsAccel = 0.0; rejectedFixes = 0
        pVV = 1.0; pVB = 0.0; pBB = .25
        lastStep = null; firstStep = null
        delta = 0.0; active = 0.0; history.clear()
    }

    private fun imuFresh(now: Double) = sensorTime?.let { now - it in 0.0..0.5 } ?: false
    private fun motionFresh(now: Double) = now - (gpsTime ?: firstStep ?: now) <= 5.0

    fun acceleration(now: Double): Double {
        if (!motionFresh(now)) return 0.0
        val a = if (imuFresh(now)) sensorAccel - accelBias
            else if (gpsTime != null && now - gpsTime!! <= 1.5) gpsAccel else 0.0
        return if (abs(a) < .05) 0.0 else a.coerceIn(-12.0, 12.0)
    }

    fun step(now: Double, forwardAccel: Double? = null) {
        if (!now.isFinite() || (lastStep != null && now < lastStep!!)) return
        if (firstStep == null) firstStep = now
        // Integrate the previously held sample; new data must not be applied
        // backwards over a scheduling pause or a sensor outage.
        val previous = lastStep ?: now
        var t = previous
        // Bound work after suspension; do not extrapolate across long pauses.
        if (now - t > .5) t = now
        while (t < now - 1e-9) {
            val dt = (now - t).coerceAtMost(.02)
            val fresh = imuFresh(t + dt) && motionFresh(t + dt)
            val raw = if (fresh) sensorAccel else 0.0
            val biasDt = if (fresh) dt else 0.0
            val a = if (fresh) raw - accelBias else 0.0
            velocity = (velocity + a * dt).coerceIn(0.0, 100.0)
            // F = [[1, -dt], [0, 1]]. Process noise allows small
            // unmodelled acceleration and slowly changing sensor bias.
            pVV = (pVV - 2*biasDt*pVB + biasDt*biasDt*pBB + .16*dt).coerceAtMost(100.0)
            pVB -= biasDt*pBB
            pBB = (pBB + .0004*dt).coerceAtMost(4.0)
            delta += raw*dt; active += biasDt
            speedMps = (speedMps + a*dt).coerceIn(0.0, 100.0)
            var correction = (velocity-speedMps)*(1-exp(-dt/.25))
            if (fresh) {
                // GPS is an absolute reference, not a competing accelerator.
                // Limit drift sync to 0.35 m/s per second and never let it undo
                // a clear current manoeuvre. With no IMU, retain GPS recovery.
                correction = correction.coerceIn(-.35*dt, .35*dt)
                if (abs(a) >= .35 && correction*a < 0.0) correction = 0.0
            }
            speedMps = (speedMps + correction).coerceIn(0.0, 100.0)
            // GPS-confirmed standstill tolerates small residual sensor offsets.
            if (gpsSpeedMps != null && gpsSpeedMps!! < .2 && t-gpsTime!! < 1.5 &&
                abs(a) < .25 && speedMps < .3) {
                velocity = 0.0; speedMps = 0.0
            }
            t += dt
            history.addLast(Integral(t, delta, active))
        }
        if (history.isEmpty() || history.last.time < now) history.addLast(Integral(now, delta, active))
        while (history.size > 1 && history.first.time < now-3.0) history.removeFirst()
        lastStep = now
        if (forwardAccel != null && forwardAccel.isFinite()) {
            sensorAccel = forwardAccel.coerceIn(-12.0, 12.0)
            sensorTime = now
        }
    }

    private fun integralAt(time: Double): Integral? {
        var before = history.peekFirst() ?: return null
        if (time < before.time) return null
        for (after in history) {
            if (after.time >= time) {
                val f = if (after.time == before.time) 0.0 else (time-before.time)/(after.time-before.time)
                return Integral(time, before.delta+(after.delta-before.delta)*f,
                    before.active+(after.active-before.active)*f)
            }
            before = after
        }
        return before
    }

    fun gps(now: Double, fixTime: Double, speed: Double, accuracyM: Double,
            speedAccuracyMps: Double? = null): Boolean {
        if (!now.isFinite() || !fixTime.isFinite() || !speed.isFinite() ||
            speed !in 0.0..100.0 || !accuracyM.isFinite() || accuracyM !in 0.0..50.0 ||
            now-fixTime !in 0.0..2.5 || (gpsTime != null && fixTime <= gpsTime!!) ||
            (lastStep != null && now < lastStep!!)) {
            rejectedFixes++; return false
        }
        step(now)
        val first = gpsTime == null
        val past = integralAt(fixTime)
        // First acquisition may precede the history. Later unrepresentable
        // measurements are rejected instead of being treated as current speed.
        if (!first && past == null) { rejectedFixes++; return false }
        // Historical speed = current speed - integral(raw accel) + bias*activeTime.
        // Measurement Jacobian H = [1, activeTime].
        val h = if (past != null) active-past.active else 0.0
        val dv = if (past != null) delta-past.delta else 0.0
        // An outage includes unmodelled vehicle motion after the prediction cap.
        // Reacquire speed without interpreting that missing motion as IMU bias.
        if (!first && now-gpsTime!! > 5.0) { pVB = 0.0; pVV += 4.0 }
        val sigma = speedAccuracyMps?.takeIf { it.isFinite() && it > 0 }?.coerceIn(.1, 10.0) ?: .5
        val r = sigma*sigma + .16*(now-fixTime)
        val residual = speed - (velocity-dv+accelBias*h)
        val s = (pVV+2*h*pVB+h*h*pBB+r).coerceAtLeast(.0001)
        if (!first && abs(residual) > maxOf(4.0, 5*kotlin.math.sqrt(s))) {
            rejectedFixes++; return false
        }
        if (first) {
            velocity = (speed+dv-accelBias*h).coerceIn(0.0, 100.0)
            speedMps = velocity
            pVV = r
        } else {
            val cV = pVV+h*pVB
            val cB = pVB+h*pBB
            velocity = (velocity+cV/s*residual).coerceIn(0.0, 100.0)
            // A single GPS discrepancy must not abruptly change the measured
            // acceleration through the bias estimate. Still allow gradual bias
            // learning during sustained motion (including larger offsets).
            val maxBiasChange = .03*(fixTime-gpsTime!!).coerceIn(0.0, 2.0)
            var biasGain = if (imuFresh(now)) cB/s else 0.0
            if (abs(residual) > 1e-9) {
                val nextBias = (accelBias+(biasGain*residual)
                    .coerceIn(-maxBiasChange, maxBiasChange)).coerceIn(-2.0, 2.0)
                biasGain = (nextBias-accelBias)/residual
            }
            accelBias += biasGain*residual
            pVV = (pVV-cV*cV/s).coerceAtLeast(1e-8)
            pVB -= cV*cB/s
            // Joseph covariance update with the actual, limited bias gain.
            pBB = (pBB-2*biasGain*cB+biasGain*biasGain*s).coerceAtLeast(1e-8)
        }
        val dt = fixTime-(gpsTime ?: fixTime)
        gpsAccel = if (dt in .2..3.0) ((speed-gpsSpeedMps!!)/dt).coerceIn(-8.0, 8.0) else 0.0
        gpsSpeedMps = speed; gpsTime = fixTime
        return true
    }

    fun diagnostics(now: Double): Map<String, Any?> = mapOf(
        "gpsSpeedMps" to gpsSpeedMps,
        "gpsAgeSeconds" to gpsTime?.let { (now-it).coerceAtLeast(0.0) },
        "sensorAgeSeconds" to sensorTime?.let { (now-it).coerceAtLeast(0.0) },
        "forwardAccelMps2" to sensorAccel,
        "correctedAccelMps2" to acceleration(now),
        "accelBiasMps2" to accelBias,
        "speedVariance" to pVV,
        "gpsAccelMps2" to gpsAccel,
        "fusedSpeedMps" to speedMps,
        "rejectedFixes" to rejectedFixes,
        "source" to when {
            !motionFresh(now) -> "GPS stale · speed held"
            gpsTime == null -> "Waiting for GPS · IMU estimate only"
            !imuFresh(now) -> "GPS · IMU unavailable"
            else -> "GPS + accelerometer · bias filter"
        }
    )
}
