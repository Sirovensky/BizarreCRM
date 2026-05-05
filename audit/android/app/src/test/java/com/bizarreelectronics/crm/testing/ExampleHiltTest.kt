package com.bizarreelectronics.crm.testing

import androidx.arch.core.executor.testing.InstantTaskExecutorRule
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.MutableCreationExtras
import com.bizarreelectronics.crm.ui.screens.settings.RateLimitBucketsViewModel
import com.bizarreelectronics.crm.util.RateLimiter
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import javax.inject.Inject

/**
 * ExampleHiltTest — smoke test verifying that the Hilt @TestInstallIn scaffold
 * wires correctly for a `@HiltAndroidTest` class.
 *
 * What this test validates:
 *  1. [HiltAndroidRule] can build the Hilt component for `SingletonComponent`.
 *  2. [TestDatabaseModule] and [TestApiModule] are resolved without errors.
 *  3. A simple `@HiltViewModel` dependency ([RateLimiter]) is field-injected.
 *  4. [HiltTestRules] runs the global-scope leak guard before injection.
 *
 * NOTE: `@HiltAndroidTest` is the annotation that signals to the Hilt annotation
 * processor that this class's test runner should use [HiltTestApplication].
 * In a local JVM unit test (`src/test/`) this requires Robolectric (via the
 * `@RunWith(AndroidJUnit4::class)` runner). If the project does not yet have
 * Robolectric on the classpath, this test will compile but fail to run —
 * see the commit body for the pre-existing blocker note.
 *
 * Plan ref: ActionPlan §1.6 line 223.
 */
@HiltAndroidTest
class ExampleHiltTest {

    /**
     * Order 0: Hilt component must be set up first so that injection works for
     * all subsequent rules and in @Before.
     */
    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    /**
     * Order 1: Forces LiveData operations onto the main thread synchronously.
     * Required for any test that reads LiveData without an actual Looper.
     */
    @get:Rule(order = 1)
    val instantTaskExecutorRule = InstantTaskExecutorRule()

    /**
     * Order 2: Validates that no GlobalScope coroutines leaked from a prior
     * test before injection starts.
     */
    @get:Rule(order = 2)
    val noLeakRule = HiltTestRules()

    /** Field-injected after [hiltRule] builds the component in [setUp]. */
    @Inject
    lateinit var rateLimiter: RateLimiter

    @Before
    fun setUp() {
        hiltRule.inject()
    }

    /**
     * Asserts that the Hilt container resolved [RateLimiter] — the sole
     * dependency of [RateLimitBucketsViewModel] — without touching the real
     * database or network.
     */
    @Test
    fun hiltInjectsSingletonRateLimiter() {
        assertNotNull(
            "RateLimiter must be non-null after Hilt injection",
            rateLimiter,
        )
    }

    /**
     * Asserts that a second injection returns the same singleton instance,
     * confirming that Hilt's SingletonComponent scope is functioning in the
     * test environment.
     */
    @Test
    fun rateLimiterIsSingleton() {
        // Inject a second reference via the same rule — should be the same object.
        val first = rateLimiter
        hiltRule.inject()
        val second = rateLimiter
        assert(first === second) {
            "RateLimiter is expected to be a singleton but got different instances: $first vs $second"
        }
    }
}
