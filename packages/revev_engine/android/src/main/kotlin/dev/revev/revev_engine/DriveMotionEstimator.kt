package dev.revev.revev_engine

import kotlin.math.abs
import kotlin.math.exp

/** Vehicle-axis inputs after gravity removal. Also used by the in-app replay harness.
 * Times are monotonic seconds, never wall-clock time. GPS anchors speed; IMU fills
 * the gaps. Dead reckoning is deliberately bounded rather than drifting forever.
 */
class DriveMotionEstimator {
    var speedMps = 0.0; private set
    var gpsSpeedMps: Double? = null; private set
    var gpsTime: Double? = null; private set
    var sensorTime: Double? = null; private set
    var sensorAccel = 0.0; private set
    var gpsAccel = 0.0; private set
    var rejectedFixes = 0; private set
    private var lastStep: Double? = null
    private var firstStep: Double? = null
    private var gpsSlopeReady = false
    private var sensorBaseline = 0.0
    private var correction = 0.0

    fun reset() {
        speedMps = 0.0
        gpsSpeedMps = null
        gpsTime = null
        sensorTime = null
        sensorAccel = 0.0
        gpsAccel = 0.0
        rejectedFixes = 0
        lastStep = null
        firstStep = null
        gpsSlopeReady = false
        sensorBaseline = 0.0
        correction = 0.0
    }

    fun acceleration(now: Double): Double {
        val imuFresh = sensorTime != null && now - sensorTime!! in 0.0..0.5
        if (gpsSlopeReady && gpsTime != null && now - gpsTime!! in 0.0..2.5) {
            // GPS supplies the sustained slope; only the changing component of
            // IMU acceleration supplies immediate pedal response. A quiet or
            // biased IMU must not turn a 1 Hz GPS ramp into a staircase.
            return (gpsAccel + if (imuFresh) sensorAccel - sensorBaseline else 0.0)
                .coerceIn(-12.0, 12.0)
        }
        return if (imuFresh) sensorAccel else 0.0
    }

    fun step(now: Double, forwardAccel: Double? = null) {
        if (!now.isFinite() || (lastStep != null && now < lastStep!!)) return
        if (firstStep == null) firstStep = now
        if (forwardAccel != null && forwardAccel.isFinite()) {
            if (sensorTime == null) sensorBaseline = forwardAccel.coerceIn(-12.0, 12.0)
            sensorAccel = forwardAccel.coerceIn(-12.0, 12.0)
            sensorTime = now
        }
        val dt = (now - (lastStep ?: now)).coerceIn(0.0, 0.25)
        lastStep = now
        sensorBaseline += (sensorAccel - sensorBaseline) * (1.0 - exp(-dt / 0.8))
        val anchor = gpsTime ?: firstStep!!
        if (now - anchor <= 5.0) {
            val accel = acceleration(now)
            // Preserve the stoplight/launch guard: small mount bias must not
            // invent movement while GPS reports standstill. A real launch or
            // the next moving GPS fix releases it.
            val atRest = speedMps < 0.5 && (gpsSpeedMps == null || gpsSpeedMps!! < 0.5)
            if (atRest && accel <= 0.25) {
                speedMps = 0.0
                correction = 0.0
            } else {
                val adjust = correction * (1.0 - exp(-dt / 0.4))
                correction -= adjust
                val advance = if (abs(accel) >= 0.08) accel * dt else 0.0
                speedMps = (speedMps + advance + adjust).coerceIn(0.0, 100.0)
            }
        }
    }

    fun gps(now: Double, fixTime: Double, speed: Double, accuracyM: Double): Boolean {
        if (!now.isFinite() || !fixTime.isFinite() || !speed.isFinite() ||
            speed !in 0.0..100.0 || !accuracyM.isFinite() || accuracyM !in 0.0..50.0 ||
            now - fixTime !in 0.0..2.5 || (gpsTime != null && fixTime <= gpsTime!!)) {
            rejectedFixes++
            return false
        }
        val dt = fixTime - (gpsTime ?: fixTime)
        val firstFix = gpsTime == null
        gpsSlopeReady = dt in 0.2..3.0
        gpsAccel = if (dt in 0.2..3.0) ((speed - gpsSpeedMps!!) / dt).coerceIn(-8.0, 8.0) else 0.0
        gpsSpeedMps = speed
        gpsTime = fixTime
        // Acquire once, then reconcile innovations over time, never jump on a
        // subsequent fix (including recovery from an outage).
        val anchor = (speed + acceleration(now) * (now - fixTime)).coerceIn(0.0, 100.0)
        if (firstFix) speedMps = anchor else correction = anchor - speedMps
        return true
    }

    fun diagnostics(now: Double): Map<String, Any?> = mapOf(
        "gpsSpeedMps" to gpsSpeedMps,
        "gpsAgeSeconds" to gpsTime?.let { (now - it).coerceAtLeast(0.0) },
        "sensorAgeSeconds" to sensorTime?.let { (now - it).coerceAtLeast(0.0) },
        "forwardAccelMps2" to sensorAccel,
        "gpsAccelMps2" to gpsAccel,
        "fusedSpeedMps" to speedMps,
        "speedCorrectionMps" to correction,
        "rejectedFixes" to rejectedFixes,
        "source" to when {
            gpsTime == null && firstStep != null && now - firstStep!! > 5.0 -> "Waiting for GPS · speed held"
            gpsTime == null -> "Waiting for GPS · IMU estimate only"
            now - gpsTime!! > 5.0 -> "GPS stale · speed held"
            now - gpsTime!! > 2.5 -> "GPS gap · IMU estimate"
            sensorTime == null || now - sensorTime!! > 0.5 -> "GPS only · no fresh accelerometer"
            else -> "GPS + accelerometer"
        }
    )
}
