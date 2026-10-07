package dev.revev.revev_engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DriveMotionEstimatorTest {
    @Test fun stationaryBiasCannotInventSpeedButLaunchIsImmediate() {
        val estimator = DriveMotionEstimator()
        estimator.step(0.0, 0.2)
        estimator.gps(0.0, 0.0, 0.0, 5.0)
        for (i in 1..40) estimator.step(i * 0.02, 0.2)
        assertEquals(0.0, estimator.speedMps)
        for (i in 41..50) estimator.step(i * 0.02, 1.5)
        assertEquals(0.3, estimator.speedMps, 0.001)
    }
    @Test fun accelerationFillsBetweenFreshGpsFixesAndBrakingReducesSpeed() {
        val estimator = DriveMotionEstimator()
        estimator.step(0.0, 2.0)
        assertTrue(estimator.gps(0.0, 0.0, 10.0, 5.0))
        for (i in 1..5) estimator.step(i * 0.1, 2.0)
        assertEquals(11.0, estimator.speedMps, 0.001)
        for (i in 6..10) estimator.step(i * 0.1, -2.0)
        assertEquals(10.0, estimator.speedMps, 0.001)
    }

    @Test fun rejectsStaleInaccurateMissingAndOutOfOrderSpeeds() {
        val estimator = DriveMotionEstimator()
        assertTrue(estimator.gps(10.0, 10.0, 8.0, 5.0))
        assertFalse(estimator.gps(10.1, 9.0, 30.0, 5.0))
        assertFalse(estimator.gps(14.0, 10.5, 30.0, 5.0))
        assertFalse(estimator.gps(14.0, 14.0, 30.0, 100.0))
        assertFalse(estimator.gps(14.0, 14.0, Double.NaN, 5.0))
        assertEquals(8.0, estimator.speedMps)
        assertEquals(4, estimator.rejectedFixes)
    }

    @Test fun outageStopsIntegratingAfterFiveSecondsAndRecovers() {
        val estimator = DriveMotionEstimator()
        estimator.step(0.0, 1.0)
        estimator.gps(0.0, 0.0, 10.0, 5.0)
        for (i in 1..100) estimator.step(i * 0.1, 1.0)
        assertEquals(15.0, estimator.speedMps, 0.01)
        assertEquals("GPS stale · speed held", estimator.diagnostics(10.0)["source"])
        assertTrue(estimator.gps(10.0, 10.0, 19.0, 5.0))
        assertEquals(15.0, estimator.speedMps, 0.01)
        for (i in 1..20) estimator.step(10.0 + i * 0.1, 0.0)
        assertTrue(estimator.speedMps in 18.9..19.1)
        estimator.reset()
        assertEquals(0.0, estimator.speedMps)
        assertEquals(null, estimator.gpsTime)
        assertEquals(null, estimator.sensorTime)
    }

    @Test fun gpsSlopeSurvivesQuietImuWithoutDoublingSteadyDemand() {
        val estimator = DriveMotionEstimator()
        estimator.gps(0.0, 0.0, 0.0, 5.0)
        estimator.gps(1.0, 1.0, 2.0, 5.0)
        assertEquals(2.0, estimator.acceleration(1.0))
        estimator.step(1.0, 1.5)
        assertEquals(2.0, estimator.acceleration(1.1))
        assertEquals(2.0, estimator.acceleration(1.6))
        assertEquals(0.0, estimator.acceleration(4.0))
    }

    @Test fun oneHertzRampWithQuietImuHasNoFixJumpsOrFlatIntervals() {
        val estimator = DriveMotionEstimator()
        estimator.step(0.0, 0.0)
        estimator.gps(0.0, 0.0, 10.0, 5.0)
        var maxError = 0.0
        for (i in 1..500) {
            val t = i * 0.02
            val before = estimator.speedMps
            estimator.step(t, 0.0)
            if (i >= 150) {
                assertTrue(estimator.speedMps - before in 0.019..0.025)
                maxError = maxOf(maxError, kotlin.math.abs(estimator.speedMps - (10 + t)))
            }
            if (i % 50 == 0) {
                val atFix = estimator.speedMps
                estimator.gps(t, t, 10 + t, 5.0)
                assertEquals(atFix, estimator.speedMps, "GPS fix jumped speed")
            }
        }
        assertTrue(maxError < 0.03, "linear ramp error=$maxError")
    }

    @Test fun brakingRampWithQuietImuFallsContinuouslyAndSettlesAtRest() {
        val estimator = DriveMotionEstimator()
        estimator.step(0.0, 0.0)
        estimator.gps(0.0, 0.0, 10.0, 5.0)
        for (i in 1..650) {
            val t = i * 0.02
            val before = estimator.speedMps
            estimator.step(t, 0.0)
            if (i in 150..450) assertTrue(estimator.speedMps < before)
            if (i % 50 == 0) {
                val atFix = estimator.speedMps
                estimator.gps(t, t, (10 - t).coerceAtLeast(0.0), 5.0)
                assertEquals(atFix, estimator.speedMps)
            }
            assertTrue(estimator.speedMps >= 0)
        }
        assertEquals(0.0, estimator.speedMps)
    }

    @Test fun delayedJitteredGpsRemainsContinuousWithoutAnyImu() {
        val estimator = DriveMotionEstimator()
        estimator.step(0.0)
        estimator.gps(0.0, 0.0, 10.0, 5.0)
        var nextFix = 1.1
        for (i in 1..500) {
            val t = i * .02
            val before = estimator.speedMps
            estimator.step(t)
            if (t > 3) {
                assertTrue(estimator.speedMps > before)
                assertTrue(kotlin.math.abs(estimator.speedMps - (10 + .5*t)) < .05)
            }
            if (t >= nextFix) {
                val atFix = estimator.speedMps
                val fixTime = t - .3
                estimator.gps(t, fixTime, 10 + .5*fixTime, 5.0)
                assertEquals(atFix, estimator.speedMps)
                nextFix += if (t.toInt() % 2 == 0) 1.1 else .9
            }
        }
    }

    @Test fun noGpsLaunchIsBoundedAndSpeedCannotGoNegative() {
        val estimator = DriveMotionEstimator()
        estimator.step(0.0, 2.0)
        for (i in 1..100) estimator.step(i * 0.1, 2.0)
        assertEquals(10.0, estimator.speedMps, 0.01)
        estimator.reset()
        estimator.step(0.0, -3.0)
        estimator.step(0.1, -3.0)
        assertEquals(0.0, estimator.speedMps)
    }
}
