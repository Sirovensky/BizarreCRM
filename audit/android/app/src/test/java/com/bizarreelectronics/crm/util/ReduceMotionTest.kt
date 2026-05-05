package com.bizarreelectronics.crm.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §31.1 — unit coverage for the §26.4 ReduceMotion decider. Pure function;
 * no Robolectric needed.
 */
class ReduceMotionTest {

    @Test fun `user preference forces reduce regardless of system scale`() {
        assertTrue(ReduceMotion.decideReduceMotion(userPref = true, systemAnimatorScale = 1f))
        assertTrue(ReduceMotion.decideReduceMotion(userPref = true, systemAnimatorScale = 0.5f))
        assertTrue(ReduceMotion.decideReduceMotion(userPref = true, systemAnimatorScale = 0f))
    }

    @Test fun `system scale zero triggers reduce when user pref off`() {
        assertTrue(ReduceMotion.decideReduceMotion(userPref = false, systemAnimatorScale = 0f))
    }

    @Test fun `default animation scale does not reduce`() {
        assertFalse(ReduceMotion.decideReduceMotion(userPref = false, systemAnimatorScale = 1f))
    }

    @Test fun `fast scale still counts as animations enabled`() {
        // Developer Options can set 0.5x — shorter but not disabled.
        assertFalse(ReduceMotion.decideReduceMotion(userPref = false, systemAnimatorScale = 0.5f))
        // And slow multipliers (1.5x, 2x) too.
        assertFalse(ReduceMotion.decideReduceMotion(userPref = false, systemAnimatorScale = 1.5f))
    }
}
