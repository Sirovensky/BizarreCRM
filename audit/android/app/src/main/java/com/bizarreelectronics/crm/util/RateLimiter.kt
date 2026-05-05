package com.bizarreelectronics.crm.util

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Token-bucket rate limiter for outbound HTTP calls (ActionPlan §1, L255-L259).
 *
 * ## Categories
 *   READ   — GET/HEAD requests, 60 tokens/min (refill 1 token every 1 000 ms)
 *   WRITE  — POST/PUT/PATCH/DELETE requests, 20 tokens/min (refill 1 token every 3 000 ms)
 *
 * ## Exemptions (L259)
 * Auth endpoints (path starts with "/auth/") and sync-queue flush calls
 * (request tagged "sync-flush") bypass client-side throttling entirely.
 * Server-side limits apply to those paths instead.
 *
 * ## Server hints (L256)
 * [recordServerHint] accepts the Retry-After duration and the current
 * X-RateLimit-Remaining value. When remaining ≤ NEAR_LIMIT_THRESHOLD the
 * affected bucket is paused for [SERVER_HINT_PAUSE_MS] as a precautionary
 * back-off. A non-null retryAfterSeconds pauses for that many seconds.
 *
 * ## UI signals (L257, L258)
 * [queueState] carries the running depth of suspended callers and a
 * "slow down" flag when depth exceeds [SLOW_DOWN_QUEUE_DEPTH]. Bucket
 * snapshots are accessible via [buckets] for the debug drawer (L258).
 *
 * Hilt delegates to [RateLimiterCore] exactly as [SessionTimeout] delegates
 * to [SessionTimeoutCore]: the thin Hilt shell wires the real clock; tests
 * supply a fake clock through [RateLimiter.forTest].
 */
@Singleton
open class RateLimiter @Inject constructor() : RateLimiterCore(
    nowMs    = System::currentTimeMillis,
    delayFn  = { ms -> delay(ms) },
    jitterFn = { ms -> (0L..(ms / 4).coerceAtLeast(1L)).random() },
) {
    companion object
}

/**
 * Testable core of [RateLimiter].
 *
 * Separated from the Hilt shell so that unit tests can supply a fake clock
 * ([nowMs]) and a fake delay ([delayFn]) without requiring Android framework
 * classes. Production code should use [RateLimiter] directly; tests should
 * use [RateLimiter.forTest].
 *
 * @param jitterFn  Maps a base-wait duration (ms) to a jitter addend (ms).
 *                  Production default: uniform random in [0, wait/4] — spreads
 *                  thundering-herd wake-ups across a 25 % window of the base
 *                  wait so callers don't all hit the server simultaneously after
 *                  a shared pause expires.  Tests inject `{ 0L }` for determinism.
 */
open class RateLimiterCore(
    internal val nowMs: () -> Long,
    internal val delayFn: suspend (Long) -> Unit,
    private  val jitterFn: (Long) -> Long = { ms -> (0L..(ms / 4).coerceAtLeast(1L)).random() },
) {
    // -------------------------------------------------------------------------
    // Public types
    // -------------------------------------------------------------------------

    enum class Category { READ, WRITE }

    /**
     * Immutable snapshot of one token bucket.
     *
     * @param category      Which category this bucket belongs to.
     * @param tokens        Current available tokens (0..capacity).
     * @param capacity      Maximum tokens (also the initial fill).
     * @param pausedUntilMs Epoch-ms at which the pause expires; null when not paused.
     */
    data class BucketState(
        val category: Category,
        val tokens: Int,
        val capacity: Int,
        val pausedUntilMs: Long?,
    )

    /**
     * Immutable snapshot of the shared queue depth across all categories.
     *
     * @param depth                  Number of callers currently suspended waiting for a token.
     * @param slowDownBannerActive   True when depth > [SLOW_DOWN_QUEUE_DEPTH] (L257).
     */
    data class QueueState(
        val depth: Int,
        val slowDownBannerActive: Boolean,
    )

    // -------------------------------------------------------------------------
    // Internal mutable bucket state (protected by a per-bucket Mutex)
    // -------------------------------------------------------------------------

    private inner class Bucket(val category: Category) {
        val mutex = kotlinx.coroutines.sync.Mutex()

        val capacity: Int = when (category) {
            Category.READ  -> READ_CAPACITY
            Category.WRITE -> WRITE_CAPACITY
        }

        val refillIntervalMs: Long = 60_000L / capacity

        // Mutable fields — only accessed while holding `mutex`.
        var tokens: Int = capacity
        var lastRefillMs: Long = nowMs()
        var pausedUntilMs: Long? = null

        /** Computes a fresh [BucketState] snapshot. Caller must hold `mutex`. */
        fun snapshot(): BucketState = BucketState(
            category = category,
            tokens = tokens,
            capacity = capacity,
            pausedUntilMs = pausedUntilMs,
        )

        /**
         * Credits tokens earned since [lastRefillMs].
         * Caller must hold `mutex`.
         */
        fun refill() {
            val now = nowMs()
            val elapsed = now - lastRefillMs
            if (elapsed >= refillIntervalMs) {
                val earned = (elapsed / refillIntervalMs).toInt()
                tokens = (tokens + earned).coerceAtMost(capacity)
                lastRefillMs = now
            }
        }
    }

    private val readBucket  = Bucket(Category.READ)
    private val writeBucket = Bucket(Category.WRITE)

    private fun bucket(category: Category): Bucket = when (category) {
        Category.READ  -> readBucket
        Category.WRITE -> writeBucket
    }

    // -------------------------------------------------------------------------
    // Public state flows
    // -------------------------------------------------------------------------

    private val _buckets = MutableStateFlow(
        mapOf(
            Category.READ  to readBucket.snapshot(),
            Category.WRITE to writeBucket.snapshot(),
        ),
    )

    /** Read-only map of bucket snapshots for debug drawer (L258). */
    val buckets: StateFlow<Map<Category, BucketState>> = _buckets.asStateFlow()

    private val _queueState = MutableStateFlow(QueueState(depth = 0, slowDownBannerActive = false))

    /** Read-only queue-depth state for the "Slow down" banner (L257). */
    val queueState: StateFlow<QueueState> = _queueState.asStateFlow()

    // -------------------------------------------------------------------------
    // Queue-depth tracking (atomic, no mutex required)
    // -------------------------------------------------------------------------

    @Volatile private var queueDepth: Int = 0

    private fun incrementQueue() {
        val depth = synchronized(this) { ++queueDepth }
        _queueState.value = QueueState(
            depth = depth,
            slowDownBannerActive = depth > SLOW_DOWN_QUEUE_DEPTH,
        )
    }

    private fun decrementQueue() {
        val depth = synchronized(this) { if (queueDepth > 0) --queueDepth else 0 }
        _queueState.value = QueueState(
            depth = depth,
            slowDownBannerActive = depth > SLOW_DOWN_QUEUE_DEPTH,
        )
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Returns true when this request is exempt from client-side rate limiting
     * per L259:
     *   - Auth endpoints: path starts with "/auth/"
     *   - Offline-queue flush: OkHttp request tag is "sync-flush"
     */
    open fun isExempt(method: String, path: String, tag: String?): Boolean {
        if (tag == SYNC_FLUSH_TAG) return true
        val normPath = path.lowercase()
        if (normPath.startsWith("/auth/") || normPath == "/auth") return true
        return false
    }

    /**
     * Acquires one token from [category]'s bucket, suspending until a token
     * is available or [ACQUIRE_TIMEOUT_MS] is reached.
     *
     * Marked `open` so test subclasses can override acquisition behaviour
     * (e.g. always return false) without requiring a full fake clock setup.
     *
     * @return true  when a token was successfully acquired.
     * @return false when the timeout was reached before a token became available.
     */
    open suspend fun acquire(category: Category): Boolean {
        val bkt = bucket(category)
        val deadline = nowMs() + ACQUIRE_TIMEOUT_MS
        return acquireInner(bkt, deadline)
    }

    /**
     * Records server-sent rate-limit hints (L256).
     *
     * - If [retryAfterSeconds] is non-null, the bucket is paused for that many seconds.
     * - If [remaining] ≤ [NEAR_LIMIT_THRESHOLD], the bucket is paused for
     *   [SERVER_HINT_PAUSE_MS] as a precautionary back-off.
     * - If both are provided, the longer pause wins.
     */
    fun recordServerHint(retryAfterSeconds: Long?, remaining: Int?, category: Category) {
        val bkt = bucket(category)
        val now = nowMs()
        var newPauseUntilMs = bkt.pausedUntilMs

        if (retryAfterSeconds != null && retryAfterSeconds > 0L) {
            val hint = now + retryAfterSeconds * 1_000L
            newPauseUntilMs = if (newPauseUntilMs == null) hint else maxOf(newPauseUntilMs, hint)
        }

        if (remaining != null && remaining <= NEAR_LIMIT_THRESHOLD) {
            val hint = now + SERVER_HINT_PAUSE_MS
            newPauseUntilMs = if (newPauseUntilMs == null) hint else maxOf(newPauseUntilMs, hint)
        }

        if (newPauseUntilMs != bkt.pausedUntilMs) {
            bkt.pausedUntilMs = newPauseUntilMs
            publishBucketSnapshot(bkt)
        }
    }

    // -------------------------------------------------------------------------
    // Internal acquisition loop (iterative — no recursion to avoid stack overflow)
    // -------------------------------------------------------------------------

    private suspend fun acquireInner(bkt: Bucket, deadline: Long): Boolean {
        // Hard retry cap prevents unbounded looping when the fake-delay in tests
        // does not advance the clock (which would make deadline never expire).
        var retriesLeft = MAX_ACQUIRE_RETRIES

        while (retriesLeft-- > 0) {
            val now = nowMs()
            if (now >= deadline) return false

            // Check pause first (no lock needed for a quick read).
            val pausedUntil = bkt.pausedUntilMs
            if (pausedUntil != null && now < pausedUntil) {
                val pauseRemaining = pausedUntil - now
                val timeoutRemaining = deadline - now

                // Fail-fast: if the server-mandated pause extends beyond our
                // remaining timeout budget, return false immediately rather than
                // waiting partial time and then timing out anyway.  The caller
                // (RateLimitInterceptor) will synthesize a local 429 response so
                // the upstream error path handles it gracefully.
                if (pauseRemaining > timeoutRemaining) return false

                val baseWait = pauseRemaining.coerceAtMost(timeoutRemaining)
                if (baseWait <= 0L) return false
                val jitter = jitterFn(baseWait)
                incrementQueue()
                delayFn(baseWait + jitter)
                decrementQueue()
                continue
            }

            // Try to take a token under the mutex.
            val acquired = bkt.mutex.withLock {
                // Lift any expired pause.
                val p = bkt.pausedUntilMs
                if (p != null && nowMs() >= p) {
                    bkt.pausedUntilMs = null
                }
                bkt.refill()
                if (bkt.tokens > 0) {
                    bkt.tokens -= 1
                    publishBucketSnapshot(bkt)
                    true
                } else {
                    false
                }
            }

            if (acquired) return true

            // No token available — wait one refill interval (+ jitter) and retry.
            val baseWait = (bkt.refillIntervalMs).coerceAtMost((deadline - nowMs()).coerceAtLeast(0L))
            if (baseWait <= 0L) return false
            val jitter = jitterFn(baseWait)

            incrementQueue()
            delayFn(baseWait + jitter)
            decrementQueue()
        }

        return false
    }

    private fun publishBucketSnapshot(bkt: Bucket) {
        val current = _buckets.value.toMutableMap()
        current[bkt.category] = bkt.snapshot()
        _buckets.value = current.toMap()
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    companion object {
        const val READ_CAPACITY  = 60
        const val WRITE_CAPACITY = 20

        /**
         * When X-RateLimit-Remaining falls at or below this value the client
         * proactively pauses to avoid hitting the server limit (L256).
         */
        const val NEAR_LIMIT_THRESHOLD = 5

        /** Duration of the proactive pause when remaining is near-zero (L256). */
        const val SERVER_HINT_PAUSE_MS = 10_000L

        /**
         * Maximum time [acquire] will wait before giving up and returning false.
         * Prevents unbounded suspension that would appear as an app hang.
         *
         * ## Rationale for 30 s (DO BOTH strategy):
         * Common server Retry-After values are 30–60 s.  The original 10 s
         * was shorter than the most common hint, causing [acquire] to return
         * false (after Bug 1 fix) for every request during a 30 s 429 window —
         * flooding the UI with synthetic 429 errors.  Raising to 30 s absorbs
         * the common case while still acting as a safety net.
         *
         * The complementary fail-fast path inside [acquireInner] handles the
         * remaining gap: when a server-mandated pause exceeds the remaining
         * timeout budget, [acquire] returns false immediately (no partial wait)
         * so the caller gets a clean, prompt synthetic 429 rather than a
         * truncated partial wait followed by the same outcome.
         *
         * Together these two measures cover both ends of the spectrum:
         *   - Short Retry-After (≤ 30 s): timeout absorbs the wait.
         *   - Long Retry-After  (> 30 s): fail-fast returns false immediately,
         *     letting the caller decide when to retry.
         */
        const val ACQUIRE_TIMEOUT_MS = 30_000L

        /**
         * Hard retry cap inside the acquisition loop.
         * In production one iteration per refill interval (1 s for READ, 3 s for
         * WRITE) means this is hit only if the server keeps sending 429s for
         * [MAX_ACQUIRE_RETRIES] consecutive refill cycles — which is effectively
         * never under normal operation. In tests with a frozen clock and a no-op
         * delay it prevents a StackOverflowError by bounding the loop.
         */
        const val MAX_ACQUIRE_RETRIES = 20

        /** Queue depth above which [QueueState.slowDownBannerActive] is set (L257). */
        const val SLOW_DOWN_QUEUE_DEPTH = 10

        /** OkHttp request tag that marks offline-queue flush calls as exempt (L259). */
        const val SYNC_FLUSH_TAG = "sync-flush"

        /** Request tag prefix for auth-path requests (for clarity in logs). */
        const val AUTH_PATH_PREFIX = "/auth/"
    }
}

// -------------------------------------------------------------------------
// Test factory — file-level extension outside the Hilt component graph
// -------------------------------------------------------------------------

/**
 * Creates a [RateLimiterCore] with a controlled clock, delay function, and
 * jitter function for JVM unit tests. Bypasses Android Context entirely.
 *
 * Accessed via `RateLimiter.forTest(...)` in tests.
 *
 * @param nowMs    Clock provider — advance this to simulate elapsed time.
 * @param delayFn  Delay implementation — typically a no-op or TestDispatcher-backed function.
 * @param jitterFn Jitter function — pass `{ 0L }` for deterministic tests.
 *                 Defaults to zero so existing tests need no changes.
 */
fun RateLimiter.Companion.forTest(
    nowMs:    () -> Long,
    delayFn:  suspend (Long) -> Unit = {},
    jitterFn: (Long) -> Long = { 0L },
): RateLimiterCore = RateLimiterCore(
    nowMs    = nowMs,
    delayFn  = delayFn,
    jitterFn = jitterFn,
)
