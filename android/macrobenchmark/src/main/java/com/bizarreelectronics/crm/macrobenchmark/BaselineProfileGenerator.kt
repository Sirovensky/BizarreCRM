package com.bizarreelectronics.crm.macrobenchmark

import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * §29 — BaselineProfile generator for the top 5 user flows.
 *
 * Running this test with `generateBaselineProfile` Gradle task produces a
 * `baseline-prof.txt` file that can be placed at `app/src/main/` and
 * committed to the repo.  The hand-written rules in `app/src/main/baseline-prof.txt`
 * were derived from static analysis; use this generator in CI to produce
 * accurate, machine-measured rules.
 *
 * ## Running
 * ```
 * ./gradlew :app:generateBaselineProfile \
 *   -Pandroid.testInstrumentationRunnerArguments.class=\
 *   com.bizarreelectronics.crm.macrobenchmark.BaselineProfileGenerator
 * ```
 *
 * This will:
 * 1. Install the ":app:release" variant on a connected device.
 * 2. Instrument each user flow listed in [generate].
 * 3. Write `app/src/main/baseline-prof.txt` (overwriting the hand-written file).
 *
 * ## Mark: [~]
 * Scaffold present; generation deferred to CI — requires connected device and
 * AGP 8.2+ `generateBaselineProfile` task wired in :app/build.gradle.kts.
 */
@RunWith(AndroidJUnit4::class)
class BaselineProfileGenerator {

    @get:Rule
    val rule = BaselineProfileRule()

    /**
     * Exercises the five top user flows to capture the hot dex methods for
     * each one.  ART records which methods are executed; the rule filters
     * to startup-critical methods and writes baseline-prof.txt.
     */
    @Test
    fun generate() = rule.collect(
        packageName = StartupBenchmark.TARGET_PACKAGE,
    ) {
        // Flow 1: Dashboard (cold start → interactive)
        pressHome()
        startActivityAndWait()
        // TODO: add UiAutomator scrolls on dashboard LazyColumn

        // Flow 2: Ticket list
        // TODO: navigate to ticket list + scroll 50 items

        // Flow 3: Inventory list
        // TODO: navigate to inventory list + scroll 50 items

        // Flow 4: POS tender
        // TODO: navigate to POS → cart → tender screen

        // Flow 5: Customer list
        // TODO: navigate to customer list + scroll 50 items
    }
}
