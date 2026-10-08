package dev.revev.revev_engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.math.abs

class DriveMotionEstimatorTest {
    @Test fun respondsBeforeNextGpsAndBrakesMonotonically() {
        val e = DriveMotionEstimator()
        e.gps(0.0, 0.0, 10.0, 5.0)
        e.step(0.0, 2.0)
        for (i in 1..40) e.step(i*.02, 2.0)
        assertEquals(11.6, e.speedMps, .001)
        assertEquals(2.0, e.acceleration(.8), .001)
        e.step(.8, -2.0)
        for (i in 41..80) {
            val before = e.speedMps
            e.step(i*.02, -2.0)
            assertTrue(e.speedMps < before)
        }
        assertEquals(10.0, e.speedMps, .001)
    }

    @Test fun delayedOneHertzGpsDoesNotIntroduceOneSecondLag() {
        val e = DriveMotionEstimator()
        e.step(0.0, 1.0)
        e.gps(0.0, 0.0, 10.0, 5.0)
        for (i in 1..1000) {
            val t = i*.02
            e.step(t, 1.0)
            if (i%50==0) {
                val before = e.speedMps
                assertTrue(e.gps(t, t-.3, 10+t-.3, 5.0, .2))
                assertEquals(before, e.speedMps, 1e-8)
            }
            assertEquals(10+t, e.speedMps, .03)
        }
    }

    @Test fun variableGpsDelayDoesNotCreateSpeedCorrectionsDuringConstantAcceleration() {
        val e=DriveMotionEstimator()
        e.step(0.0,.7); e.gps(0.0,0.0,10.0,5.0)
        for(i in 1..1000) {
            val t=i*.02
            e.step(t,.7)
            if(i%50==0) {
                val delay=if(i%100==0) .6 else .15
                assertTrue(e.gps(t,t-delay,10+.7*(t-delay),5.0,.2))
            }
            assertEquals(10+.7*t,e.speedMps,.01)
        }
    }

    @Test fun learnsBiasWithoutInventingLongTermAcceleration() {
        val e = DriveMotionEstimator()
        e.step(0.0, .2)
        e.gps(0.0, 0.0, 10.0, 5.0)
        for (i in 1..3000) {
            val t=i*.02
            e.step(t, .2)
            if (i%50==0) e.gps(t, t-.3, 10.0, 5.0, .2)
        }
        assertEquals(.2, e.accelBias, .03)
        assertEquals(10.0, e.speedMps, .05)
        assertEquals(0.0, e.acceleration(60.0), .05)
    }

    @Test fun gpsCorrectionIsContinuousAndConverges() {
        val e=DriveMotionEstimator()
        e.gps(0.0, 0.0, 10.0, 5.0)
        for (i in 1..500) {
            val t=i*.02
            e.step(t)
            if (i%50==0) {
                val before=e.speedMps
                assertTrue(e.gps(t,t,12.0,5.0))
                assertEquals(before,e.speedMps)
            }
        }
        assertEquals(12.0,e.speedMps,.05)
    }

    @Test fun staleImuDoesNotIntegrateAcrossGapAndFreshSampleIsNotRetroactive() {
        val e=DriveMotionEstimator()
        e.gps(0.0,0.0,10.0,5.0)
        e.step(0.0,2.0)
        for (i in 1..100) e.step(i*.02)
        assertTrue(e.speedMps in 10.9..11.01)
        val before=e.speedMps
        e.step(20.0,8.0)
        assertEquals(before,e.speedMps)
        assertEquals(0.0,e.acceleration(20.0))
    }

    @Test fun gpsOutageBoundsDeadReckoningAndRecovers() {
        val e=DriveMotionEstimator()
        e.gps(0.0,0.0,10.0,5.0)
        e.step(0.0,1.0)
        for (i in 1..500) e.step(i*.02,1.0)
        assertEquals(15.0,e.speedMps,.03)
        val before=e.speedMps
        assertTrue(e.gps(10.0,10.0,16.0,5.0))
        assertEquals(before,e.speedMps)
        for (i in 501..600) e.step(i*.02,0.0)
        assertTrue(e.speedMps in 15.0..16.2)
    }

    @Test fun zeroSpeedIsStableAndLaunchIsImmediate() {
        val e=DriveMotionEstimator()
        e.gps(0.0,0.0,0.0,5.0)
        for (i in 1..250) {
            val t=i*.02
            e.step(t,if(i%2==0) .1 else -.1)
            if(i%50==0) e.gps(t,t,0.0,5.0)
            assertEquals(0.0,e.speedMps)
        }
        e.step(5.0,1.0)
        for(i in 251..270) e.step(i*.02,1.0)
        assertTrue(e.speedMps>.35)
    }

    @Test fun rejectsBadFixesAndOutliers() {
        val e=DriveMotionEstimator()
        e.gps(0.0,0.0,8.0,5.0)
        assertFalse(e.gps(.1,0.0,8.0,5.0))
        assertFalse(e.gps(4.0,.5,8.0,5.0))
        assertFalse(e.gps(1.0,1.0,8.0,100.0))
        assertFalse(e.gps(1.0,1.0,Double.NaN,5.0))
        assertFalse(e.gps(1.0,1.0,80.0,5.0))
        assertEquals(5,e.rejectedFixes)
        assertEquals(8.0,e.speedMps)
        e.reset()
        assertEquals(0.0,e.speedMps)
        assertEquals(0.0,e.accelBias)
        assertEquals(null,e.gpsTime)
    }

    @Test fun brakingReachesZeroWithoutNegativeSpeed() {
        val e=DriveMotionEstimator()
        e.gps(0.0,0.0,3.0,5.0); e.step(0.0,-1.0)
        for(i in 1..250) {
            val t=i*.02
            e.step(t,if(t<3) -1.0 else 0.0)
            if(i%50==0) e.gps(t,t,(3-t).coerceAtLeast(0.0),5.0)
            assertTrue(e.speedMps>=0.0)
        }
        assertEquals(0.0,e.speedMps,.01)
    }

    @Test fun lowConfidenceGpsHasLessInfluence() {
        val good=DriveMotionEstimator(); val poor=DriveMotionEstimator()
        for(e in listOf(good,poor)) e.gps(0.0,0.0,10.0,5.0)
        good.gps(1.0,1.0,12.0,5.0,.2)
        poor.gps(1.0,1.0,12.0,5.0,3.0)
        for(i in 1..50) { good.step(1+i*.02); poor.step(1+i*.02) }
        assertTrue(good.speedMps>poor.speedMps+1.0)
    }

    @Test fun timerFrequencyDoesNotChangeEstimate() {
        val a=DriveMotionEstimator(); val b=DriveMotionEstimator()
        for(e in listOf(a,b)) { e.gps(0.0,0.0,10.0,5.0); e.step(0.0,1.0) }
        for(i in 1..100) a.step(i*.01,1.0)
        for(i in 1..20) b.step(i*.05,1.0)
        assertTrue(abs(a.speedMps-b.speedMps)<.001)
    }
}
