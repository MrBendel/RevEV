package dev.revev.revev_engine

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.assertEquals

class ForwardAccelerationFilterTest {
    @Test fun brakingReversesAccelerationWithinFortyMilliseconds() {
        val f = ForwardAccelerationFilter()
        repeat(50) { f.update(2.0, .02) }
        f.update(-2.0, .02)
        assertTrue(f.update(-2.0, .02) < -.9)
        repeat(3) { f.update(-2.0, .02) }
        assertTrue(f.update(-2.0, .02) < -1.9)
    }

    @Test fun smallAlternatingVibrationDoesNotBecomeThrottle() {
        val f = ForwardAccelerationFilter()
        repeat(500) { i -> assertTrue(abs(f.update(if(i%2==0) .15 else -.15, .02)) < .03) }
        f.reset()
        assertEquals(0.0, f.update(.04, .02))
    }

    @Test fun repeatedShortStopsTrackWithoutWaitingForGps() {
        val f = ForwardAccelerationFilter()
        val e = DriveMotionEstimator()
        e.gps(0.0, 0.0, 0.0, 5.0)
        e.step(0.0, 0.0)
        fun speed(t: Double): Double {
            val p = t.coerceAtLeast(0.0)%4.5
            return when { p < 2 -> 2*p; p < 4 -> 4-2*(p-2); else -> 0.0 }
        }
        for (i in 1..675) {
            val t=i*.02
            val p=t%4.5
            val raw=when { p<2 -> 2.0; p<4 -> -2.0; else -> 0.0 }
            e.step(t, f.update(raw, .02))
            if(i%50==0) e.gps(t,t-.6,speed(t-.6),5.0,.5)
            assertTrue(abs(e.speedMps-speed(t)) < .25, "speed at $t: ${e.speedMps} vs ${speed(t)}")
            if(p in 2.08..3.9) assertTrue(e.acceleration(t) < -1.7, "braking at $t")
            if(p in .08..1.9) assertTrue(e.acceleration(t) > 1.7, "launch at $t")
            if(p in 4.15..4.48) assertTrue(e.speedMps < .2, "stop before next launch at $t")
        }
    }
}
