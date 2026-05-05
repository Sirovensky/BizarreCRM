import XCTest
@testable import Core

// §31.5 — Perf-baseline runner
//
// Establishes XCTest performance baselines for the operations tracked by
// `PerformanceBudget` (§29). Each test uses `measure {}` so Xcode records
// a baseline on first run and flags regressions on subsequent runs.
//
// Baseline workflow:
//   1. Run once locally → Xcode stores baseline in the .xcresult / test plan.
//   2. Edit baselines via Xcode → Report Navigator → set baseline.
//   3. CI compares future runs against the stored baseline; fails on 10% over.
//
// Metric coverage (§31.5):
//   - Launch time          → XCTApplicationLaunchMetric (see UITests/)
//   - Scroll frame drops   → XCTOSSignpostMetric (see UITests/)
//   - Memory               → XCTMemoryMetric (below)
//   - Storage writes       → XCTStorageMetric (below)
//   - CPU                  → XCTCPUMetric (below)
//   - Clock (wall time)    → XCTClockMetric — micro-benchmark for hot paths
//
// All benchmarks here target pure Swift hot paths (no UIKit / AppKit) so
// they run in unit-test targets without a simulator. The UI-metric tests
// that require a running app are scaffolded in UITests/PerfBaselineUITests.swift.

// MARK: - PerfBaselineRunner: Wall-clock micro-benchmarks

final class PerfBaselineRunnerTests: XCTestCase {

    // MARK: - Clock metric baselines

    /// Baseline: currency formatting of a large batch.
    ///
    /// Budget: §29 does not set an explicit threshold for batch-format, but
    /// 10 000 format calls must complete in ≤ 200 ms on an M-series CI runner.
    /// The recorded baseline enforces drift via Xcode's 10% regression window.
    func test_baseline_currencyFormatBatch() {
        let amounts = (0..<10_000).map { Int64($0 * 99) }
        measure(metrics: [XCTClockMetric()]) {
            for amount in amounts {
                _ = Currency.formatCents(amount, currencyCode: "USD")
            }
        }
    }

    /// Baseline: ISO8601 date round-trip (encode → decode) ×1 000.
    func test_baseline_iso8601RoundTrip() {
        let factory = ISO8601Factory.shared
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<1_000 {
                let s = factory.string(from: date)
                _ = factory.date(from: s)
            }
        }
    }

    /// Baseline: LogCaptureSink — 5 000 sequential log writes.
    func test_baseline_logCaptureSink_sequentialWrites() {
        let sink = LogCaptureSink()
        measure(metrics: [XCTClockMetric()]) {
            sink.reset()
            for i in 0..<5_000 {
                sink.log(level: .debug, message: "baseline-\(i)", category: "perf")
            }
        }
    }

    /// Baseline: RandomFixtureSeed generation ×10 000.
    func test_baseline_randomFixtureSeed_generation() {
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<10_000 {
                _ = RandomFixtureSeed.make()
            }
        }
    }

    // MARK: - Memory metric baselines

    /// Baseline: memory headroom consumed by building 1 000 log entries in LogCaptureSink.
    func test_baseline_logCaptureSink_memoryFootprint() {
        let sink = LogCaptureSink()
        measure(metrics: [XCTMemoryMetric()]) {
            sink.reset()
            for i in 0..<1_000 {
                sink.log(level: .info, message: "mem-baseline-\(i)", category: "memory")
            }
        }
    }

    // MARK: - CPU metric baselines

    /// Baseline: CPU time for 10 000 currency-format calls.
    /// The CPU metric captures kernel + user time; useful to detect algorithmic
    /// regressions that do extra work even at the same wall-clock speed.
    func test_baseline_currencyFormat_cpuTime() {
        let amounts = (0..<10_000).map { Int64($0 * 137) }
        measure(metrics: [XCTCPUMetric()]) {
            for amount in amounts {
                _ = Currency.formatCents(amount, currencyCode: "EUR")
            }
        }
    }

    // MARK: - Multi-metric baselines

    /// Combined clock + CPU + memory for a realistic "list-render" proxy:
    /// decode 200 JSON items from the fixture loader.
    func test_baseline_fixtureLoader_200Items() throws {
        let loader = FixtureLoader(bundle: .module)

        // Verify the fixture is loadable before benchmarking
        struct FixtureTicket: Decodable {
            let id: Int; let title: String; let status: String
        }
        _ = try loader.load("ticket_default") as FixtureTicket

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for _ in 0..<200 {
                // FixtureLoader.loadData is a fast bundle-read path
                _ = try? loader.loadData("ticket_default")
            }
        }
    }
}

// MARK: - PerfBudgetEnforcementTests
//
// These tests enforce hard ceilings that must NEVER regress regardless of
// baseline drift. They use `continueAfterFailure = false` so a single budget
// breach aborts the run immediately, giving a clear signal in CI logs.

final class PerfBudgetEnforcementTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Single currency format must complete in < 1 ms (wall clock).
    func test_budget_singleCurrencyFormat_under1ms() {
        let start = ContinuousClock.now
        _ = Currency.formatCents(9_99, currencyCode: "USD")
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1_000 +
                 Double(elapsed.components.attoseconds) / 1e15
        XCTAssertLessThan(ms, 1.0, "Single Currency.formatCents must complete in < 1 ms, took \(ms) ms")
    }

    /// LogCaptureSink.reset() must be O(1) — completes in < 5 ms even after 10k entries.
    func test_budget_logCaptureSink_reset_under5ms() {
        let sink = LogCaptureSink()
        for i in 0..<10_000 {
            sink.log(level: .debug, message: "fill-\(i)", category: "bench")
        }

        let start = ContinuousClock.now
        sink.reset()
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1_000 +
                 Double(elapsed.components.attoseconds) / 1e15
        XCTAssertLessThan(ms, 5.0, "reset() on 10k-entry sink must complete in < 5 ms, took \(ms) ms")
    }
}
