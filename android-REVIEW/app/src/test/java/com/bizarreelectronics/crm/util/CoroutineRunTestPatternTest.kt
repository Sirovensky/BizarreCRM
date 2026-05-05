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
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §31.1 — Demonstrates and verifies the canonical `runTest + StandardTestDispatcher`
 * pattern used across all ViewModel and Repository coroutine tests in this project.
 *
 * These tests are the reference implementation for:
 *   - `runTest { }` auto-advances virtual time over all `delay()` calls.
 *   - `StandardTestDispatcher` queues coroutines rather than executing them
 *     eagerly; callers use `advanceUntilIdle()` / `advanceTimeBy()` for control.
 *   - `TestScope.currentTime` advances correctly alongside `delay`.
 *   - Concurrent launches in a TestScope do not race — they are deterministic.
 *
 * No production code is exercised here; the tests exist to validate the
 * test-infrastructure pattern so that bugs in how coroutines are driven are
 * caught at the testing-utility layer rather than discovered as false positives
 * in business-logic tests.
 *
 * ActionPlan §31.1 — Kotlin coroutines test via `runTest` + `StandardTestDispatcher`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CoroutineRunTestPatternTest {

    // -------------------------------------------------------------------------
    // 1. runTest skips real time for delay()
    // -------------------------------------------------------------------------

    @Test
    fun `runTest advances virtual clock over delay without real-wall-clock wait`() = runTest {
        val before = currentTime
        delay(10_000)
        val after = currentTime
        // Virtual time must have advanced by exactly 10 000 ms; the test should
        // complete in milliseconds of real wall-clock time.
        assertEquals("Virtual clock must advance by delay duration", 10_000L, after - before)
    }

    // -------------------------------------------------------------------------
    // 2. StandardTestDispatcher queues work — advanceUntilIdle drains it
    // -------------------------------------------------------------------------

    @Test
    fun `StandardTestDispatcher queues launched coroutines - advanceUntilIdle drains all`() = runTest {
        val results = mutableListOf<Int>()
        launch { results.add(1) }
        launch { results.add(2) }
        launch { results.add(3) }
        // Not yet drained — the launches are queued.
        // advanceUntilIdle() runs all pending coroutines to completion.
        advanceUntilIdle()
        assertEquals("All three launched coroutines must complete", listOf(1, 2, 3), results)
    }

    // -------------------------------------------------------------------------
    // 3. advanceTimeBy moves virtual clock by an exact amount
    // -------------------------------------------------------------------------

    @Test
    fun `advanceTimeBy moves virtual clock by exact amount`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val scope = TestScope(dispatcher)
        var reached500ms = false
        var reached1000ms = false

        scope.launch {
            delay(500)
            reached500ms = true
            delay(500)
            reached1000ms = true
        }

        scope.advanceTimeBy(500)
        assertTrue("Coroutine paused at 500 ms delay should have reached first checkpoint", reached500ms)
        assertTrue("Coroutine should NOT have reached 1000 ms checkpoint yet", !reached1000ms)

        scope.advanceTimeBy(500)
        scope.advanceUntilIdle()
        assertTrue("Coroutine should reach 1000 ms checkpoint after second advance", reached1000ms)
    }

    // -------------------------------------------------------------------------
    // 4. Flow emissions collected with runTest
    // -------------------------------------------------------------------------

    @Test
    fun `StateFlow emission is collected synchronously in runTest`() = runTest {
        val flow = MutableStateFlow(0)
        assertEquals(0, flow.first())

        flow.value = 42
        assertEquals(42, flow.first())
    }

    // -------------------------------------------------------------------------
    // 5. Sequential delay totals accumulate in virtual time
    // -------------------------------------------------------------------------

    @Test
    fun `sequential delays accumulate correctly in virtual time`() = runTest {
        val t0 = currentTime
        delay(100)
        delay(200)
        delay(300)
        val elapsed = currentTime - t0
        assertEquals("Sequential delays must sum correctly", 600L, elapsed)
    }

    // -------------------------------------------------------------------------
    // 6. Concurrent launches with different delays complete in correct order
    // -------------------------------------------------------------------------

    @Test
    fun `concurrent launches with different delays complete in virtual-time order`() = runTest {
        val order = mutableListOf<String>()
        launch {
            delay(200)
            order.add("slow")
        }
        launch {
            delay(100)
            order.add("fast")
        }
        advanceUntilIdle()
        assertEquals(
            "fast coroutine (delay 100) must complete before slow (delay 200)",
            listOf("fast", "slow"),
            order,
        )
    }
}
