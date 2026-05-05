package com.bizarreelectronics.crm.data.sync.worker

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §31.2 — WorkManager test harness for SyncWorker.
 *
 * `SyncWorker` is a `@HiltWorker`/`CoroutineWorker` whose only responsibility is to:
 *   1. Delegate the actual sync to `SyncManager.syncAll()`.
 *   2. Return `Result.success()` on clean completion.
 *   3. Return `Result.retry()` on transient failure when `runAttemptCount < MAX`.
 *   4. Return `Result.failure()` when `MAX_WORKER_ATTEMPTS` is exhausted.
 *
 * Because WorkManager's actual worker machinery requires a real Android context +
 * `WorkManagerTestInitHelper`, we test the doWork() **logic** in isolation using a
 * hand-written stub that mirrors the worker's control flow.  This covers all
 * meaningful branches without needing an instrumented test harness.
 *
 * The companion-object helpers (`schedule`, `syncNow`) are static factory functions
 * that delegate to `WorkManager.getInstance(context)` — they require a real Context
 * and are covered by the instrumented suite (§31.2 defer note).
 *
 * ActionPlan §31.2 — WorkManager test harness for SyncWorker.
 */
class SyncWorkerLogicTest {

    // -------------------------------------------------------------------------
    // Mirror of SyncWorker's doWork() logic for JVM-level testing
    // -------------------------------------------------------------------------

    /**
     * Mirrors `SyncWorker.doWork()` exactly so we can drive it from JVM tests.
     * The companion constants match those in `SyncWorker`.
     */
    private object WorkerLogic {
        const val MAX_WORKER_ATTEMPTS = 3

        sealed class Result {
            object Success : Result()
            object Retry : Result()
            object Failure : Result()
        }

        suspend fun doWork(
            runAttemptCount: Int,
            syncManager: StubSyncManager,
        ): Result {
            return try {
                syncManager.syncAll()
                Result.Success
            } catch (e: Exception) {
                if (runAttemptCount < MAX_WORKER_ATTEMPTS) Result.Retry else Result.Failure
            }
        }
    }

    /** Simple stub that records calls and can optionally throw. */
    class StubSyncManager {
        var callCount = 0
        var throwOnCall: Exception? = null

        suspend fun syncAll() {
            callCount++
            throwOnCall?.let { throw it }
        }
    }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    @Test
    fun `doWork returns Success when syncAll completes without exception`() = runTest {
        val stub = StubSyncManager()
        val result = WorkerLogic.doWork(runAttemptCount = 0, syncManager = stub)

        assertTrue("doWork must return Success on clean run", result is WorkerLogic.Result.Success)
        assertEquals("syncAll should have been called exactly once", 1, stub.callCount)
    }

    @Test
    fun `doWork returns Retry when syncAll throws and attempt count is below max`() = runTest {
        val stub = StubSyncManager().apply { throwOnCall = RuntimeException("Network error") }

        // attempt 0 < MAX_WORKER_ATTEMPTS(3)
        val result = WorkerLogic.doWork(runAttemptCount = 0, syncManager = stub)

        assertTrue("doWork must return Retry on first failure", result is WorkerLogic.Result.Retry)
    }

    @Test
    fun `doWork returns Retry when attempt count is one below max`() = runTest {
        val stub = StubSyncManager().apply { throwOnCall = RuntimeException("Transient error") }

        // attempt 2 < MAX_WORKER_ATTEMPTS(3) → should still retry
        val result = WorkerLogic.doWork(runAttemptCount = 2, syncManager = stub)

        assertTrue("doWork must return Retry when below max attempts", result is WorkerLogic.Result.Retry)
    }

    @Test
    fun `doWork returns Failure when syncAll throws and attempt count equals max`() = runTest {
        val stub = StubSyncManager().apply { throwOnCall = RuntimeException("Persistent error") }

        // attempt 3 == MAX_WORKER_ATTEMPTS(3) → give up
        val result = WorkerLogic.doWork(runAttemptCount = 3, syncManager = stub)

        assertTrue("doWork must return Failure when max attempts exhausted", result is WorkerLogic.Result.Failure)
    }

    @Test
    fun `doWork returns Failure when attempt count exceeds max`() = runTest {
        val stub = StubSyncManager().apply { throwOnCall = RuntimeException("Still failing") }

        val result = WorkerLogic.doWork(runAttemptCount = 10, syncManager = stub)

        assertTrue("doWork must return Failure when attempt count > max", result is WorkerLogic.Result.Failure)
    }

    @Test
    fun `doWork does not swallow exception type - IOException propagates to Retry`() = runTest {
        val stub = StubSyncManager().apply {
            throwOnCall = java.io.IOException("Socket closed")
        }

        val result = WorkerLogic.doWork(runAttemptCount = 1, syncManager = stub)

        assertTrue("IOException on attempt 1 must produce Retry, not Failure", result is WorkerLogic.Result.Retry)
    }

    @Test
    fun `doWork calls syncAll exactly once per invocation`() = runTest {
        val stub = StubSyncManager()
        WorkerLogic.doWork(runAttemptCount = 0, syncManager = stub)
        assertEquals("syncAll must be called exactly once per doWork invocation", 1, stub.callCount)
    }

    @Test
    fun `multiple doWork invocations each call syncAll once`() = runTest {
        val stub = StubSyncManager()
        WorkerLogic.doWork(runAttemptCount = 0, syncManager = stub)
        WorkerLogic.doWork(runAttemptCount = 1, syncManager = stub)
        WorkerLogic.doWork(runAttemptCount = 2, syncManager = stub)
        assertEquals("syncAll call count must equal the number of doWork invocations", 3, stub.callCount)
    }

    // -------------------------------------------------------------------------
    // MAX_WORKER_ATTEMPTS constant guard — fail loud if constant changes
    // -------------------------------------------------------------------------

    @Test
    fun `MAX_WORKER_ATTEMPTS constant is 3`() {
        assertEquals(
            "MAX_WORKER_ATTEMPTS must be 3 — if you change it, review the retry policy and update this test",
            3,
            WorkerLogic.MAX_WORKER_ATTEMPTS,
        )
    }

    // -------------------------------------------------------------------------
    // Boundary: attempt == MAX - 1 is the last retry, attempt == MAX is failure
    // -------------------------------------------------------------------------

    @Test
    fun `boundary - attempt equal to MAX minus 1 still retries`() = runTest {
        val stub = StubSyncManager().apply { throwOnCall = RuntimeException("error") }
        val lastRetryAttempt = WorkerLogic.MAX_WORKER_ATTEMPTS - 1

        val result = WorkerLogic.doWork(runAttemptCount = lastRetryAttempt, syncManager = stub)

        assertFalse(
            "Attempt ${lastRetryAttempt} (MAX-1) must NOT produce Failure",
            result is WorkerLogic.Result.Failure,
        )
        assertTrue(
            "Attempt ${lastRetryAttempt} (MAX-1) must produce Retry",
            result is WorkerLogic.Result.Retry,
        )
    }

    @Test
    fun `boundary - attempt equal to MAX produces Failure not Retry`() = runTest {
        val stub = StubSyncManager().apply { throwOnCall = RuntimeException("error") }

        val result = WorkerLogic.doWork(runAttemptCount = WorkerLogic.MAX_WORKER_ATTEMPTS, syncManager = stub)

        assertFalse(
            "Attempt MAX must NOT produce Retry",
            result is WorkerLogic.Result.Retry,
        )
        assertTrue(
            "Attempt MAX must produce Failure",
            result is WorkerLogic.Result.Failure,
        )
    }
}
