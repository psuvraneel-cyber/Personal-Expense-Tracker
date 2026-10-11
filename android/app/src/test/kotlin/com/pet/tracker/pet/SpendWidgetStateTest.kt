package com.pet.tracker.pet

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SpendWidgetStateTest {
    private val oct11 = LocalDate.of(2026, 10, 11)

    @Test
    fun `same day shows spending and spreads budget over remaining days`() {
        val s = SpendWidgetState.from("2026-10-11", "1240.5", "2100", false, oct11)
        assertTrue(s.hasData)
        assertEquals(1240.5, s.spentToday, 0.001)
        // 21 days left in October including the 11th.
        assertEquals(100.0, s.leftToday!!, 0.001)
    }

    @Test
    fun `after midnight today's spend resets but the budget still applies`() {
        val s = SpendWidgetState.from("2026-10-10", "999", "2100", false, oct11)
        assertEquals(0.0, s.spentToday, 0.001)
        assertEquals(100.0, s.leftToday!!, 0.001)
    }

    @Test
    fun `last month's budget is not carried into a new month`() {
        val s = SpendWidgetState.from("2026-09-30", "50", "900", false, oct11)
        assertNull(s.leftToday)
    }

    @Test
    fun `overspent budget shows zero left`() {
        val s = SpendWidgetState.from("2026-10-11", "0", "-500", false, oct11)
        assertEquals(0.0, s.leftToday!!, 0.001)
    }

    @Test
    fun `no budget means no left-today figure`() {
        assertNull(SpendWidgetState.from("2026-10-11", "10", null, false, oct11).leftToday)
    }

    @Test
    fun `locked or never written hides amounts`() {
        val locked = SpendWidgetState.from("2026-10-11", "10", "100", true, oct11)
        assertTrue(locked.locked)
        assertFalse(locked.hasData)
        assertFalse(SpendWidgetState.from(null, null, null, false, oct11).hasData)
        assertFalse(SpendWidgetState.from("garbage", "1", "1", false, oct11).hasData)
    }
}
