package dev.revev.revev_engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DriveMotionEstimatorTest {
    @Test fun interpolatesLinearlyOverExactlyOneSecond() {
        val e = DriveMotionEstimator()
        e.gps(0.0, 0.0, 10.0, 5.0)
        e.gps(1.0, 1.0, 12.0, 5.0)
        assertEquals(10.0, e.speedMps)
        assertEquals(2.0, e.acceleration(1.0))
        e.step(1.25, 0.0)
        assertEquals(10.5, e.speedMps)
        e.step(1.5, -4.0)
        assertEquals(11.0, e.speedMps, "Current IMU must not distort buffered GPS interpolation")
        e.step(2.0)
        assertEquals(12.0, e.speedMps)
        assertEquals(0.0, e.acceleration(2.0))
    }

    @Test fun oneHertzRampTracksExactlyOneSecondBehind() {
        val e = DriveMotionEstimator()
        e.gps(0.0, 0.0, 10.0, 5.0)
        for (i in 1..500) {
            val t = i * .02
            e.step(t, 0.0)
            if (i >= 50) assertEquals(10 + t - 1, e.speedMps, 1e-8)
            if (i % 50 == 0) {
                val before = e.speedMps
                e.gps(t, t, 10 + t, 5.0)
                assertEquals(before, e.speedMps)
            }
        }
    }

    @Test fun brakingNeverOvershootsAndSettlesAtZero() {
        val e = DriveMotionEstimator()
        e.gps(0.0, 0.0, 10.0, 5.0)
        for (i in 1..600) {
            val t = i * .02
            val previous = e.speedMps
            e.step(t, .3)
            assertTrue(e.speedMps in 0.0..previous)
            if (i % 50 == 0) e.gps(t, t, (10-t).coerceAtLeast(0.0), 5.0)
        }
        assertEquals(0.0, e.speedMps)
    }

    @Test fun earlyLateAndDelayedFixesRetargetWithoutJumping() {
        val e = DriveMotionEstimator()
        e.gps(0.0, 0.0, 10.0, 5.0)
        for (arrival in listOf(1.1, 2.0, 3.2, 4.0, 5.1)) {
            e.step(arrival)
            val previous = e.speedMps
            assertTrue(e.gps(arrival, arrival-.3, 10+arrival-.3, 5.0))
            assertEquals(previous, e.speedMps)
            val target = e.gpsSpeedMps!!
            e.step(arrival+.2)
            assertEquals(previous + (target-previous)*.2, e.speedMps, 1e-8)
        }
    }

    @Test fun interpolationUsesTimeNotCallbackCount() {
        val fast = DriveMotionEstimator()
        val slow = DriveMotionEstimator()
        for (e in listOf(fast, slow)) {
            e.gps(0.0, 0.0, 5.0, 5.0)
            e.gps(1.0, 1.0, 8.0, 5.0)
        }
        for (i in 1..50) fast.step(1+i*.02)
        slow.step(2.0)
        assertEquals(8.0, fast.speedMps)
        assertEquals(fast.speedMps, slow.speedMps)
    }

    @Test fun missingFixFinishesSegmentThenHoldsAndRecoversSmoothly() {
        val e = DriveMotionEstimator()
        e.gps(0.0, 0.0, 10.0, 5.0)
        e.gps(1.0, 1.0, 12.0, 5.0)
        for (i in 11..100) e.step(i*.1, 2.0)
        assertEquals(12.0, e.speedMps)
        assertEquals("GPS stale · speed held", e.diagnostics(10.0)["source"])
        e.gps(10.0, 10.0, 19.0, 5.0)
        assertEquals(12.0, e.speedMps)
        e.step(10.5)
        assertEquals(15.5, e.speedMps)
        e.step(11.0)
        assertEquals(19.0, e.speedMps)
        e.reset()
        assertEquals(0.0, e.speedMps)
        assertEquals(null, e.gpsTime)
        assertEquals(null, e.sensorTime)
    }

    @Test fun stationaryGpsCannotBeMovedBySensorNoise() {
        val e = DriveMotionEstimator()
        e.gps(0.0, 0.0, 0.0, 5.0)
        for (i in 1..100) e.step(i*.02, if (i%2==0) .8 else -.8)
        assertEquals(0.0, e.speedMps)
        assertEquals(0.0, e.acceleration(2.0))
    }

    @Test fun rejectsInvalidStaleAndOutOfOrderObservations() {
        val e = DriveMotionEstimator()
        assertTrue(e.gps(10.0, 10.0, 8.0, 5.0))
        assertFalse(e.gps(10.1, 9.0, 30.0, 5.0))
        assertFalse(e.gps(14.0, 10.5, 30.0, 5.0))
        assertFalse(e.gps(14.0, 14.0, 30.0, 100.0))
        assertFalse(e.gps(14.0, 14.0, Double.NaN, 5.0))
        assertEquals(8.0, e.speedMps)
        assertEquals(4, e.rejectedFixes)
    }

    @Test fun noGpsImuEstimateRemainsBounded() {
        val e = DriveMotionEstimator()
        e.step(0.0, 2.0)
        for (i in 1..100) e.step(i*.1, 2.0)
        assertEquals(10.0, e.speedMps, .01)
        e.reset()
        e.step(0.0, -.2)
        e.step(.1, -.2)
        assertEquals(0.0, e.speedMps)
    }
}
