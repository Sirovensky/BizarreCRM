package com.bizarreelectronics.crm.util

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Demonstrates and exercises Kotlin coroutines testing patterns (ActionPlan §31.1).
 *
 * Each test uses [runTest] with a [StandardTestDispatcher] so coroutine execution
 * is deterministic and clock-controlled. These patterns serve as a canonical
 * reference for the rest of the codebase:
 *
 *   1. Simple suspend function: verify suspending value with [runTest].
 *   2. Delayed emission: [advanceTimeBy] fast-forwards virtual time.
 *   3. Concurrent launch: [advanceUntilIdle] drains all pending work.
 *   4. StateFlow collector: flow emission is testable synchronously.
 *   5. Exception propagation: suspend throws are caught cleanly in [runTest].
 *   6. Nested [delay] is virtual, no real wall-clock time consumed.
 *   7. [TestScope] can be constructed explicitly for shared state across tests.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CoroutinesRunTestTest {

    // ── 1. Simple suspend function ────────────────────────────────────────────

    @Test
    fun `runTest — suspend function returns computed value`() = runTest {
        val result = suspendCompute(6, 7)
        assertEquals(42, result)
    }

    // ── 2. Delayed emission fast-forwarded by advanceTimeBy ──────────────────

    @Test
    fun `advanceTimeBy — delayed value is available after virtual clock advance`() = runTest {
        var result = 0
        launch {
            delay(500)
            result = 99
        }
        assertEquals("Before advance, result must still be 0", 0, result)
        advanceTimeBy(501)
        assertEquals("After advancing past delay, result must be 99", 99, result)
    }

    // ── 3. Concurrent launches drained by advanceUntilIdle ───────────────────

    @Test
    fun `advanceUntilIdle — drains all pending coroutines`() = runTest {
        val completed = mutableListOf<Int>()
        repeat(5) { i ->
            launch {
                delay((i + 1) * 100L)
                completed.add(i)
            }
        }
        advanceUntilIdle()
        assertEquals("All 5 coroutines must complete", 5, completed.size)
        assertEquals(listOf(0, 1, 2, 3, 4), completed.sorted())
    }

    // ── 4. StateFlow emission is testable synchronously ──────────────────────

    @Test
    fun `StateFlow — emitted value read synchronously after advanceUntilIdle`() = runTest {
        val flow = MutableStateFlow(0)
        launch {
            delay(200)
            flow.value = 7
        }
        advanceUntilIdle()
        assertEquals(7, flow.value)
    }

    @Test
    fun `StateFlow first() — collector receives initial value immediately`() = runTest {
        val flow = MutableStateFlow("initial")
        val value = flow.first()
        assertEquals("initial", value)
    }

    // ── 5. Exception from suspend function propagates to runTest ─────────────

    @Test(expected = IllegalStateException::class)
    fun `runTest — suspend exception propagates to test`() = runTest {
        suspendThrows()
    }

    // ── 6. delay inside runTest consumes virtual time only ────────────────────

    @Test
    fun `delay inside runTest is virtual — wall-clock unaffected`() = runTest {
        val before = System.currentTimeMillis()
        delay(10_000)   // 10 virtual seconds — must complete instantly
        val elapsed = System.currentTimeMillis() - before
        // Wall-clock elapsed should be well under 1 s.
        assertTrue(
            "Virtual delay should consume near-zero real time, got ${elapsed}ms",
            elapsed < 3000,
        )
    }

    // ── 7. StandardTestDispatcher with explicit TestScope ────────────────────

    @Test
    fun `StandardTestDispatcher — coroutines do not start until explicitly advanced`() {
        val dispatcher = StandardTestDispatcher()
        val scope = TestScope(dispatcher)
        var ran = false
        scope.launch { ran = true }
        assertFalse("Coroutine must not have run before advancing", ran)
        scope.advanceUntilIdle()
        assertTrue("Coroutine must have run after advanceUntilIdle", ran)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private suspend fun suspendCompute(a: Int, b: Int): Int {
        delay(1)  // ensures suspension to validate runTest handles it
        return a * b
    }

    private suspend fun suspendThrows(): Nothing {
        delay(1)
        throw IllegalStateException("deliberate test exception")
    }
}
