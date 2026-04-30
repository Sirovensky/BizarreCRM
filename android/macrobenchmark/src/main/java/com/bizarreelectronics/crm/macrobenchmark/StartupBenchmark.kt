package com.bizarreelectronics.crm.macrobenchmark

import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.FrameTimingMetric
import androidx.benchmark.macro.StartupMode
import androidx.benchmark.macro.StartupTimingMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * §29.8 — Macrobenchmark scaffold for cold-start + frame-timing.
 *
 * ## What this measures
 *   - [StartupTimingMetric]: timeToInitialDisplay + timeToFullDisplay
 *   - [FrameTimingMetric]: p50 / p90 / p99 frame durations during scroll
 *
 * ## Running
 * ```
 * ./gradlew :macrobenchmark:connectedBenchmarkAndroidTest \
 *   -Pandroid.testInstrumentationRunnerArguments.class=\
 *   com.bizarreelectronics.crm.macrobenchmark.StartupBenchmark
 * ```
 *
 * ## Marker
 * This is a scaffold — the benchmark cannot be executed in this session
 * because Macrobenchmark requires a connected physical device and an
 * instrumented test runner (cannot be launched via the CI build step alone).
 * Mark: [~] (scaffold present, run deferred to CI).
 *
 * ## Companion flows
 * See [TicketListScrollBenchmark], [InventoryScrollBenchmark],
 * [PosTenderBenchmark], [CustomerListScrollBenchmark] for the other four
 * top-5 user-flow benchmarks.
 */
@RunWith(AndroidJUnit4::class)
class StartupBenchmark {

    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    /**
     * Cold-start benchmark with no pre-compilation — establishes the worst-case
     * baseline that a user without cloud profile delivery would experience.
     */
    @Test
    fun startupColdNoCompilation() = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = listOf(StartupTimingMetric()),
        compilationMode = CompilationMode.None(),
        startupMode = StartupMode.COLD,
        iterations = 5,
        setupBlock = {
            // Press home and clear the recent-apps list so the process is
            // fully cold on each iteration.
            pressHome()
        },
    ) {
        startActivityAndWait()
    }

    /**
     * Cold-start benchmark with Partial compilation (baseline profile).
     * Mirrors the production experience after Play cloud-profile delivery
     * or after profileinstaller runs at install time.
     */
    @Test
    fun startupColdBaselineProfile() = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = listOf(StartupTimingMetric()),
        compilationMode = CompilationMode.Partial(),
        startupMode = StartupMode.COLD,
        iterations = 5,
        setupBlock = { pressHome() },
    ) {
        startActivityAndWait()
    }

    /**
     * Dashboard scroll: measures FrameTimingMetric after the screen is loaded.
     * p50 ≤ 16ms and < 5 % janky frames (§29.2) are the pass criteria.
     */
    @Test
    fun dashboardScroll() = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = listOf(FrameTimingMetric()),
        compilationMode = CompilationMode.Partial(),
        startupMode = StartupMode.WARM,
        iterations = 3,
        setupBlock = { pressHome() },
    ) {
        startActivityAndWait()
        // TODO: add UiAutomator interaction to scroll the dashboard LazyColumn
        // once test-IDs are applied to the list container.
    }

    companion object {
        const val TARGET_PACKAGE = "com.bizarreelectronics.crm"
    }
}
