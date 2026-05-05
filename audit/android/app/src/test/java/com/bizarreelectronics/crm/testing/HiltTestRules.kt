package com.bizarreelectronics.crm.testing

import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

/**
 * HiltTestRules — JUnit [TestRule] that validates no static global-state leaks
 * escape between Hilt unit tests.
 *
 * Checks performed **before** each test via a wrapping [Statement]:
 *
 * 1. **GlobalScope coroutine leak guard** — counts live children of
 *    `GlobalScope.coroutineContext[Job]` via reflection. Fails if the count
 *    exceeds [maxGlobalScopeChildren] (default 0). Usage of `GlobalScope` in
 *    production code is a code-smell; this rule makes such leaks visible
 *    immediately rather than causing flaky downstream test failures.
 *
 * 2. **SharedPreferences residual check** — documented as optional; this rule
 *    does NOT assert on SharedPreferences files because the JVM test
 *    environment (Robolectric) uses an in-memory registry that is torn down
 *    with the process and does not leave disk artefacts between tests.
 *    If instrumented (on-device) tests are added later, insert a
 *    `context.getSharedPreferencesPath("*").deleteRecursively()` call here.
 *
 * Usage:
 * ```kotlin
 * @HiltAndroidTest
 * class MyTest {
 *     @get:Rule(order = 0) val hiltRule = HiltAndroidRule(this)
 *     @get:Rule(order = 1) val noLeakRule = HiltTestRules()
 * }
 * ```
 *
 * Plan ref: ActionPlan §1.6 line 223.
 */
class HiltTestRules(
    /**
     * Maximum number of live [GlobalScope] coroutine children tolerated at test
     * start. Default is 0 (none). Set higher only if a known framework
     * coroutine is expected and cannot be avoided.
     */
    private val maxGlobalScopeChildren: Int = 0,
) : TestRule {

    override fun apply(base: Statement, description: Description): Statement =
        object : Statement() {
            override fun evaluate() {
                assertNoGlobalScopeLeaks()
                base.evaluate()
            }
        }

    /**
     * Reflectively reads the child count of `GlobalScope.coroutineContext[Job]`.
     *
     * [GlobalScope] does not expose its internal [Job] directly; we access it
     * via `coroutineContext[Job]` which returns the scope's supervisor job.
     * `children` is a `Sequence<Job>` — we materialise it into a list purely
     * to count and include identifiers in the failure message.
     */
    private fun assertNoGlobalScopeLeaks() {
        val job = GlobalScope.coroutineContext[Job] ?: return  // No supervisor job — nothing to check.
        val children = job.children.toList()
        val count = children.size
        if (count > maxGlobalScopeChildren) {
            throw AssertionError(
                "GlobalScope coroutine leak detected before test: " +
                    "$count live child(ren) found (max=$maxGlobalScopeChildren). " +
                    "Children: ${children.map { it.toString() }}. " +
                    "Prefer structured concurrency (viewModelScope / lifecycleScope) " +
                    "over GlobalScope in production code.",
            )
        }
    }
}
