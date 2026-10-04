package dev.revev.revev_engine

import kotlin.math.abs

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
    }

    fun acceleration(now: Double): Double {
        // A GPS derivative is a fallback when the IMU is unavailable, not a second
        // copy of acceleration to add to the IMU and double the driver's demand.
        return if (sensorTime != null && now - sensorTime!! in 0.0..0.5) sensorAccel
        else if (gpsTime != null && now - gpsTime!! in 0.0..2.5) gpsAccel else 0.0
    }

    fun step(now: Double, forwardAccel: Double? = null) {
        if (!now.isFinite() || (lastStep != null && now < lastStep!!)) return
        if (firstStep == null) firstStep = now
        if (forwardAccel != null && forwardAccel.isFinite()) {
            sensorAccel = forwardAccel.coerceIn(-12.0, 12.0)
            sensorTime = now
        }
        val dt = (now - (lastStep ?: now)).coerceIn(0.0, 0.25)
        lastStep = now
        val anchor = gpsTime ?: firstStep!!
        if (now - anchor <= 5.0) {
            val accel = acceleration(now)
            // Preserve the stoplight/launch guard: small mount bias must not
            // invent movement while GPS reports standstill. A real launch or
            // the next moving GPS fix releases it.
            val atRest = speedMps < 0.5 && (gpsSpeedMps == null || gpsSpeedMps!! < 0.5)
            if (atRest && accel <= 0.25) {
                speedMps = 0.0
            } else if (abs(accel) >= 0.08) {
                speedMps = (speedMps + accel * dt).coerceIn(0.0, 100.0)
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
        gpsAccel = if (dt in 0.2..3.0) ((speed - gpsSpeedMps!!) / dt).coerceIn(-8.0, 8.0) else 0.0
        gpsSpeedMps = speed
        gpsTime = fixTime
        // Anchor at the reported fix time, extrapolating only its bounded age.
        speedMps = (speed + acceleration(now) * (now - fixTime)).coerceIn(0.0, 100.0)
        return true
    }

    fun diagnostics(now: Double): Map<String, Any?> = mapOf(
        "gpsSpeedMps" to gpsSpeedMps,
        "gpsAgeSeconds" to gpsTime?.let { (now - it).coerceAtLeast(0.0) },
        "sensorAgeSeconds" to sensorTime?.let { (now - it).coerceAtLeast(0.0) },
        "forwardAccelMps2" to sensorAccel,
        "gpsAccelMps2" to gpsAccel,
        "fusedSpeedMps" to speedMps,
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
