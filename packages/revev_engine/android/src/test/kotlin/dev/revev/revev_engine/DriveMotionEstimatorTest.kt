package dev.revev.revev_engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DriveMotionEstimatorTest {
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
        assertEquals(19.0, estimator.speedMps)
        estimator.reset()
        assertEquals(0.0, estimator.speedMps)
        assertEquals(null, estimator.gpsTime)
        assertEquals(null, estimator.sensorTime)
    }

    @Test fun gpsAccelerationIsFallbackWithoutDoublingImuDemand() {
        val estimator = DriveMotionEstimator()
        estimator.gps(0.0, 0.0, 0.0, 5.0)
        estimator.gps(1.0, 1.0, 2.0, 5.0)
        assertEquals(2.0, estimator.acceleration(1.0))
        estimator.step(1.0, 1.5)
        assertEquals(1.5, estimator.acceleration(1.1))
        assertEquals(2.0, estimator.acceleration(1.6))
        assertEquals(0.0, estimator.acceleration(4.0))
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
