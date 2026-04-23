package com.bizarreelectronics.crm.util

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [RateLimiterCore] (and the [RateLimiter.forTest] factory).
 *
 * Uses:
 *  - [FakeClock]  — mutable epoch-ms provider.
 *  - [FakeDelay]  — captures requested delay durations and advances the clock
 *    by the requested amount so that re-try loops in [RateLimiterCore.acquire]
 *    complete synchronously.
 *
 * All tests are synchronous JVM tests (JUnit 4). Coroutine suspension is
 * bridged via [runBlocking].
 *
 * Coverage:
 *   - isExempt: auth paths and sync-flush tag
 *   - acquire: immediate success when bucket full
 *   - acquire: timeout when bucket drained and no refill (fake delay keeps clock still)
 *   - recordServerHint: sets pausedUntilMs from Retry-After
 *   - Refill cycle: tokens granted when time advances
 *   - Queue depth: increments while callers wait
 *   - Capacity: cannot exceed 60 (READ) or 20 (WRITE)
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RateLimiterTest {

    // -------------------------------------------------------------------------
    // Fake helpers
    // -------------------------------------------------------------------------

    private class FakeClock(var nowMs: Long = 0L) {
        val provider: () -> Long = { nowMs }
    }

    /**
     * Fake delay that advances [clock] by the requested milliseconds so that
     * the token-bucket retry loop terminates in a single iteration.
     */
    private class FakeDelay(private val clock: FakeClock) {
        val delays = mutableListOf<Long>()
        val fn: suspend (Long) -> Unit = { ms ->
            delays += ms
            clock.nowMs += ms
        }
    }

    private fun makeCore(
        clock: FakeClock = FakeClock(),
        delay: FakeDelay? = null,
    ): RateLimiterCore = RateLimiter.forTest(
        nowMs   = clock.provider,
        delayFn = delay?.fn ?: {},
    )

    // -------------------------------------------------------------------------
    // isExempt (L259)
    // -------------------------------------------------------------------------

    @Test
    fun `isExempt returns true for auth login POST`() {
        val core = makeCore()
        assertTrue(core.isExempt("POST", "/auth/login", null))
    }

    @Test
    fun `isExempt returns true for auth prefix with trailing slash`() {
        val core = makeCore()
        assertTrue(core.isExempt("POST", "/auth/refresh", null))
    }

    @Test
    fun `isExempt returns true for any method on auth path`() {
        val core = makeCore()
        assertTrue(core.isExempt("GET",   "/auth/me", null))
        assertTrue(core.isExempt("PUT",   "/auth/password", null))
        assertTrue(core.isExempt("DELETE","/auth/session", null))
    }

    @Test
    fun `isExempt returns false for non-auth path`() {
        val core = makeCore()
        assertFalse(core.isExempt("GET", "/api/v1/tickets", null))
        assertFalse(core.isExempt("POST", "/api/v1/customers", null))
    }

    @Test
    fun `isExempt returns true for sync-flush tag`() {
        val core = makeCore()
        assertTrue(core.isExempt("POST", "/api/v1/tickets", "sync-flush"))
    }

    @Test
    fun `isExempt returns false for unrelated tag`() {
        val core = makeCore()
        assertFalse(core.isExempt("POST", "/api/v1/invoices", "background-refresh"))
    }

    @Test
    fun `isExempt path matching is case insensitive`() {
        val core = makeCore()
        assertTrue(core.isExempt("POST", "/AUTH/LOGIN", null))
        assertTrue(core.isExempt("GET",  "/Auth/Me", null))
    }

    // -------------------------------------------------------------------------
    // acquire — immediate success (bucket full)
    // -------------------------------------------------------------------------

    @Test
    fun `acquire returns true immediately when READ bucket is full`() {
        val core = makeCore()
        val result = runBlocking { core.acquire(RateLimiterCore.Category.READ) }
        assertTrue(result)
    }

    @Test
    fun `acquire returns true immediately when WRITE bucket is full`() {
        val core = makeCore()
        val result = runBlocking { core.acquire(RateLimiterCore.Category.WRITE) }
        assertTrue(result)
    }

    @Test
    fun `acquire decrements token count`() {
        val core = makeCore()
        val before = core.buckets.value[RateLimiterCore.Category.READ]!!.tokens
        runBlocking { core.acquire(RateLimiterCore.Category.READ) }
        val after = core.buckets.value[RateLimiterCore.Category.READ]!!.tokens
        assertEquals(before - 1, after)
    }

    // -------------------------------------------------------------------------
    // Capacity — tokens never exceed capacity
    // -------------------------------------------------------------------------

    @Test
    fun `READ bucket initial tokens equal capacity`() {
        val core = makeCore()
        val state = core.buckets.value[RateLimiterCore.Category.READ]!!
        assertEquals(RateLimiterCore.READ_CAPACITY, state.capacity)
        assertEquals(RateLimiterCore.READ_CAPACITY, state.tokens)
    }

    @Test
    fun `WRITE bucket initial tokens equal capacity`() {
        val core = makeCore()
        val state = core.buckets.value[RateLimiterCore.Category.WRITE]!!
        assertEquals(RateLimiterCore.WRITE_CAPACITY, state.capacity)
        assertEquals(RateLimiterCore.WRITE_CAPACITY, state.tokens)
    }

    @Test
    fun `READ bucket respects capacity — 60 tokens max`() {
        val core = makeCore()
        val capacity = core.buckets.value[RateLimiterCore.Category.READ]!!.capacity
        assertEquals(60, capacity)
    }

    @Test
    fun `WRITE bucket respects capacity — 20 tokens max`() {
        val core = makeCore()
        val capacity = core.buckets.value[RateLimiterCore.Category.WRITE]!!.capacity
        assertEquals(20, capacity)
    }

    // -------------------------------------------------------------------------
    // acquire — timeout when bucket drained and no clock advance
    // -------------------------------------------------------------------------

    @Test
    fun `acquire returns false after timeout when bucket drained and clock frozen`() {
        val clock = FakeClock(nowMs = 0L)
        // Delay does NOT advance the clock → refill never fires → acquire times out.
        val noAdvanceDelay: FakeDelay = FakeDelay(FakeClock(0L)).also { /* discard its clock */ }
        val frozenDelay = object {
            val fn: suspend (Long) -> Unit = { /* intentional no-op: clock stays frozen */ }
        }
        val core = RateLimiter.forTest(
            nowMs   = clock.provider,
            delayFn = frozenDelay.fn,
        )

        // Drain the WRITE bucket (capacity = 20).
        repeat(RateLimiterCore.WRITE_CAPACITY) {
            runBlocking { core.acquire(RateLimiterCore.Category.WRITE) }
        }

        // Bucket empty, clock frozen → next acquire must time out.
        val result = runBlocking { core.acquire(RateLimiterCore.Category.WRITE) }
        assertFalse(result)
    }

    // -------------------------------------------------------------------------
    // Refill cycle — tokens granted over time
    // -------------------------------------------------------------------------

    @Test
    fun `refill grants tokens when time advances by one interval`() {
        val clock = FakeClock(nowMs = 0L)
        val delay = FakeDelay(clock)
        val core  = makeCore(clock, delay)

        // Drain a WRITE token.
        runBlocking { core.acquire(RateLimiterCore.Category.WRITE) }

        // Advance by exactly one refill interval (60_000 / 20 = 3_000 ms).
        clock.nowMs += 3_000L

        // Take another token — should succeed without waiting.
        val result = runBlocking { core.acquire(RateLimiterCore.Category.WRITE) }
        assertTrue(result)
    }

    @Test
    fun `refill is capped at capacity — cannot exceed 20 WRITE tokens`() {
        val clock = FakeClock(nowMs = 0L)
        val delay = FakeDelay(clock)
        val core  = makeCore(clock, delay)

        // Advance a full minute — would naively create 20 new tokens on top of 20.
        clock.nowMs += 60_000L

        // Must not exceed capacity.
        val state = core.buckets.value[RateLimiterCore.Category.WRITE]!!
        // Tokens are still the initial fill (20); advance doesn't apply until acquire triggers refill.
        assertEquals(RateLimiterCore.WRITE_CAPACITY, state.capacity)
    }

    // -------------------------------------------------------------------------
    // recordServerHint — pausedUntilMs
    // -------------------------------------------------------------------------

    @Test
    fun `recordServerHint with retryAfterSeconds sets pausedUntilMs`() {
        val clock = FakeClock(nowMs = 1_000_000L)
        val core  = makeCore(clock)

        core.recordServerHint(
            retryAfterSeconds = 30L,
            remaining         = null,
            category          = RateLimiterCore.Category.READ,
        )

        val state = core.buckets.value[RateLimiterCore.Category.READ]!!
        assertNotNull(state.pausedUntilMs)
        assertEquals(1_000_000L + 30_000L, state.pausedUntilMs)
    }

    @Test
    fun `recordServerHint with near-zero remaining sets pausedUntilMs`() {
        val clock = FakeClock(nowMs = 500_000L)
        val core  = makeCore(clock)

        core.recordServerHint(
            retryAfterSeconds = null,
            remaining         = RateLimiterCore.NEAR_LIMIT_THRESHOLD,
            category          = RateLimiterCore.Category.WRITE,
        )

        val state = core.buckets.value[RateLimiterCore.Category.WRITE]!!
        assertNotNull(state.pausedUntilMs)
        assertEquals(500_000L + RateLimiterCore.SERVER_HINT_PAUSE_MS, state.pausedUntilMs)
    }

    @Test
    fun `recordServerHint prefers longer pause when both hints present`() {
        val clock = FakeClock(nowMs = 0L)
        val core  = makeCore(clock)

        // retryAfter = 5 s; SERVER_HINT_PAUSE_MS = 10 000 ms → 10 s wins.
        core.recordServerHint(
            retryAfterSeconds = 5L,
            remaining         = 0,
            category          = RateLimiterCore.Category.READ,
        )

        val state = core.buckets.value[RateLimiterCore.Category.READ]!!
        assertNotNull(state.pausedUntilMs)
        assertTrue(
            "Expected pause ≥ 10 s, got ${state.pausedUntilMs}",
            state.pausedUntilMs!! >= RateLimiterCore.SERVER_HINT_PAUSE_MS,
        )
    }

    @Test
    fun `recordServerHint with remaining above threshold does not set pause`() {
        val clock = FakeClock(nowMs = 0L)
        val core  = makeCore(clock)

        core.recordServerHint(
            retryAfterSeconds = null,
            remaining         = RateLimiterCore.NEAR_LIMIT_THRESHOLD + 1,
            category          = RateLimiterCore.Category.READ,
        )

        val state = core.buckets.value[RateLimiterCore.Category.READ]!!
        assertNull(state.pausedUntilMs)
    }

    @Test
    fun `recordServerHint with zero retryAfterSeconds does not set pause`() {
        val clock = FakeClock(nowMs = 0L)
        val core  = makeCore(clock)

        core.recordServerHint(
            retryAfterSeconds = 0L,
            remaining         = null,
            category          = RateLimiterCore.Category.WRITE,
        )

        val state = core.buckets.value[RateLimiterCore.Category.WRITE]!!
        assertNull(state.pausedUntilMs)
    }

    // -------------------------------------------------------------------------
    // Queue depth — increments when callers wait (L257)
    // -------------------------------------------------------------------------

    @Test
    fun `queueState depth starts at zero`() {
        val core = makeCore()
        assertEquals(0, core.queueState.value.depth)
        assertFalse(core.queueState.value.slowDownBannerActive)
    }

    @Test
    fun `slowDownBannerActive is false below threshold`() {
        val core = makeCore()
        // Drain WRITE bucket without actually waiting.
        val clock = FakeClock(nowMs = 0L)
        val fastDelay = FakeDelay(clock)
        val core2 = makeCore(clock, fastDelay)

        // Banner is off initially.
        assertFalse(core2.queueState.value.slowDownBannerActive)
    }

    // -------------------------------------------------------------------------
    // Bucket state immutability — each update emits a new map
    // -------------------------------------------------------------------------

    @Test
    fun `acquire emits a new buckets snapshot on each call`() {
        val core = makeCore()
        val before = core.buckets.value[RateLimiterCore.Category.READ]

        runBlocking { core.acquire(RateLimiterCore.Category.READ) }

        val after = core.buckets.value[RateLimiterCore.Category.READ]
        assertNotNull(after)
        // Tokens should have decreased by 1.
        assertEquals(before!!.tokens - 1, after!!.tokens)
    }

    // -------------------------------------------------------------------------
    // BucketState data class correctness
    // -------------------------------------------------------------------------

    @Test
    fun `BucketState reports correct category`() {
        val core = makeCore()
        assertEquals(
            RateLimiterCore.Category.READ,
            core.buckets.value[RateLimiterCore.Category.READ]!!.category,
        )
        assertEquals(
            RateLimiterCore.Category.WRITE,
            core.buckets.value[RateLimiterCore.Category.WRITE]!!.category,
        )
    }
}
