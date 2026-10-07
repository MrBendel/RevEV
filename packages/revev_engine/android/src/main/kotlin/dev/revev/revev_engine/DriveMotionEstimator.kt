package dev.revev.revev_engine

import kotlin.math.abs

/** Monotonic vehicle-axis telemetry shared by live Drive and the replay harness.
 * Each new GPS reading becomes a one-second linear segment from the currently
 * presented speed. At 1 Hz this interpolates consecutive fixes with one second
 * of added latency, without predicting an unknown future speed.
 */
class DriveMotionEstimator {
    companion object { const val interpolationSeconds = 1.0 }
    var speedMps = 0.0; private set
    var gpsSpeedMps: Double? = null; private set
    var gpsTime: Double? = null; private set
    var sensorTime: Double? = null; private set
    var sensorAccel = 0.0; private set
    var gpsAccel = 0.0; private set
    var rejectedFixes = 0; private set
    private var lastStep: Double? = null
    private var firstStep: Double? = null
    private var segmentTime = 0.0
    private var segmentFrom = 0.0
    private var segmentTo = 0.0

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
        segmentTime = 0.0
        segmentFrom = 0.0
        segmentTo = 0.0
    }

    fun acceleration(now: Double): Double {
        if (gpsTime != null) {
            // Match load/shift demand to the delayed speed trajectory. Feeding
            // current IMU demand here would move shifting ahead of that speed.
            return if (now >= segmentTime && now < segmentTime + interpolationSeconds)
                ((segmentTo - segmentFrom) / interpolationSeconds).coerceIn(-12.0, 12.0)
            else 0.0
        }
        return if (sensorTime != null && now - sensorTime!! in 0.0..0.5) sensorAccel else 0.0
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
        if (gpsTime != null) {
            val fraction = ((now - segmentTime) / interpolationSeconds).coerceIn(0.0, 1.0)
            speedMps = segmentFrom + (segmentTo - segmentFrom) * fraction
            return
        }
        // Before the first GPS fix only, retain the bounded IMU launch estimate.
        if (now - firstStep!! <= 5.0) {
            val accel = acceleration(now)
            if (speedMps < 0.5 && accel <= 0.25) speedMps = 0.0
            else if (abs(accel) >= 0.08) speedMps = (speedMps + accel * dt).coerceIn(0.0, 100.0)
        }
    }

    fun gps(now: Double, fixTime: Double, speed: Double, accuracyM: Double): Boolean {
        if (!now.isFinite() || !fixTime.isFinite() || !speed.isFinite() ||
            speed !in 0.0..100.0 || !accuracyM.isFinite() || accuracyM !in 0.0..50.0 ||
            now - fixTime !in 0.0..2.5 || (gpsTime != null && fixTime <= gpsTime!!) ||
            (lastStep != null && now < lastStep!!)) {
            rejectedFixes++
            return false
        }
        step(now)
        val firstFix = gpsTime == null
        val dt = fixTime - (gpsTime ?: fixTime)
        gpsAccel = if (dt in 0.2..3.0) ((speed - gpsSpeedMps!!) / dt).coerceIn(-8.0, 8.0) else 0.0
        gpsSpeedMps = speed
        gpsTime = fixTime
        // Acquire the initial anchor immediately. Later fixes never jump output:
        // early/late arrivals and recovery retarget from the current segment.
        if (firstFix) speedMps = speed
        segmentFrom = speedMps
        segmentTo = speed
        segmentTime = now
        return true
    }

    fun diagnostics(now: Double): Map<String, Any?> = mapOf(
        "gpsSpeedMps" to gpsSpeedMps,
        "gpsAgeSeconds" to gpsTime?.let { (now - it).coerceAtLeast(0.0) },
        "sensorAgeSeconds" to sensorTime?.let { (now - it).coerceAtLeast(0.0) },
        "forwardAccelMps2" to sensorAccel,
        "gpsAccelMps2" to gpsAccel,
        "fusedSpeedMps" to speedMps,
        "interpolationSeconds" to interpolationSeconds,
        "rejectedFixes" to rejectedFixes,
        "source" to when {
            gpsTime == null && firstStep != null && now - firstStep!! > 5.0 -> "Waiting for GPS · speed held"
            gpsTime == null -> "Waiting for GPS · IMU estimate only"
            now - gpsTime!! > 5.0 -> "GPS stale · speed held"
            now >= segmentTime + interpolationSeconds -> "GPS · speed held"
            else -> "GPS · 1 s interpolation"
        }
    )
}
