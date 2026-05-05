# iOS Performance Benchmark Harness

Scroll-fps + cold-start + list-render + battery benchmark suite for the §29 gate requirements.

---

## Running the benchmarks

```bash
# Run scroll tests only (Phase 3 scaffold)
bash ios/scripts/bench.sh

# Run scroll tests + aggregate JSON baseline (§29)
bash ios/scripts/perf-report.sh
```

`bench.sh` runs the five `*ScrollTests` classes via `xcodebuild` against an
iPhone 15 simulator and writes results to `/tmp/ios-perf.xcresult`.

`perf-report.sh` runs `bench.sh`, then parses the xcresult via `xcresulttool`
and writes `docs/perf-baseline.json` for PR diff checks.

Open the bundle in Xcode (File → Open) to see per-iteration graphs for
each `XCTOSSignpostMetric` and `XCTClockMetric`.

---

## Performance budgets (§29)

All budgets are defined in `PerformanceBudgets.swift`:

| Metric | Budget | Test |
|---|---|---|
| Scroll frame p95 | 16.67 ms (60 fps) | `*ScrollTests` |
| Cold start | 1500 ms (iPhone SE 3) | `ColdStartTests` |
| Warm start | 250 ms | `ColdStartTests` |
| List render (tab → first row) | 500 ms | `ListRenderTests` |
| Idle memory footprint | 200 MB | `MemoryProbeTests` + `MemoryProbe` |
| Network request timeout | 10 000 ms | (enforced at `APIClient`) |
| Progress indicator show | 500 ms | (enforced at `APIClient`) |

---

## Battery bench — REQUIRES PHYSICAL DEVICE

`BatteryBenchTests` samples `UIDevice.current.batteryLevel` every 15 seconds
over a 2-minute scripted exercise. Results are written to `/tmp/battery-bench.csv`.

**Simulator always reports `batteryLevel = 1.0`** — the test automatically
skips unless `TEST_ENV=device` is set.

To run on a physical device:

```bash
TEST_ENV=device xcodebuild test \
  -project ios/BizarreCRM.xcodeproj \
  -scheme BizarreCRM \
  -destination "platform=iOS,id=<DEVICE_UDID>" \
  -only-testing:BizarreCRMUITests/BatteryBenchTests
```

Acceptable drain: < 2% over 2 minutes. Exceeding 2% emits an
`XCTExpectFailure` (non-strict) — it does not block the build but
should be investigated.

---

## Interpreting metrics

| Metric | Source | Pass criterion |
|---|---|---|
| Scroll deceleration duration | `XCTOSSignpostMetric.scrollDecelerationMetric` | p95 < 16.67 ms |
| Navigation transition duration | `XCTOSSignpostMetric.navigationTransitionMetric` | p95 < 300 ms |
| Wall-clock time per iteration | `XCTClockMetric` | informational / baseline |
| Cold start | wall clock (terminate → tab bar) | < 1500 ms |
| List render | wall clock (tab tap → `list.ready`) | < 500 ms |

**Frame time math:**

- 60 fps → 1000 ms / 60 = **16.67 ms** per frame (iPhone SE minimum)
- 120 fps → 1000 ms / 120 = **8.33 ms** per frame (iPad Pro M-series ProMotion target)

---

## MemoryProbe

`ios/Packages/Core/Sources/Core/Metrics/MemoryProbe.swift` exposes:

```swift
let mb = MemoryProbe.currentResidentMB()   // → Double (MB)
MemoryProbe.sample(label: "after-sync")    // logs via AppLog.perf
```

Uses `mach_task_basic_info` → `phys_footprint` (the memory-pressure-relevant
footprint shown in Instruments → Allocations). Compiles on macOS/Catalyst via
`#if canImport(Darwin)`. Returns `0` on non-Darwin (Linux CI) — tests skip
the positive-value assertion there.

---

## Harness-mode wiring (TODO — follow-up task)

The test classes launch the app with `-PerformanceHarness 1`. The host app
must detect this flag and swap every real repository for a mock implementation
that returns 1000 deterministic rows so the list always has enough data to
exercise scrolling without a live network or populated database.

**Wiring pattern** — add to `App/AppServices.swift` (advisory-lock required
per `agent-ownership.md`):

```swift
import Factory

// Inside AppServices.init() or a dedicated configure() method:
if CommandLine.arguments.contains("-PerformanceHarness") {
    Container.shared.ticketRepository.register { MockTicketRepository(rowCount: 1000) }
    Container.shared.customerRepository.register { MockCustomerRepository(rowCount: 1000) }
    Container.shared.inventoryRepository.register { MockInventoryRepository(rowCount: 1000) }
    Container.shared.invoiceRepository.register { MockInvoiceRepository(rowCount: 1000) }
    Container.shared.communicationsRepository.register { MockCommunicationsRepository(rowCount: 1000) }
}
```

The first cell in each list must set `.accessibilityIdentifier("list.ready")` so
`ListRenderTests` can measure time-to-first-row precisely.

**TODO checklist for the follow-up PR:**

- [ ] Add `MockTicketRepository` in `Packages/Tickets/Sources/Tickets/Mocks/`
- [ ] Add `MockCustomerRepository` in `Packages/Customers/Sources/Customers/Mocks/`
- [ ] Add `MockInventoryRepository` in `Packages/Inventory/Sources/Inventory/Mocks/`
- [ ] Add `MockInvoiceRepository` in `Packages/Invoices/Sources/Invoices/Mocks/`
- [ ] Add `MockCommunicationsRepository` in `Packages/Communications/Sources/Communications/Mocks/`
- [ ] Wire all five into `AppServices.swift` under the `-PerformanceHarness` guard
- [ ] Set `.accessibilityIdentifier("list.ready")` on the first visible cell in each list view
- [ ] Set `.accessibilityIdentifier("root.tabBar")` on the root `TabView` in `RootView.swift`
- [ ] Re-run `bash ios/scripts/bench.sh` and confirm green gate

Until this wiring lands, `bench.sh` will fail (the app launches but lists are
empty, causing XCUITest element lookups to time out). This is expected and
documented — the harness scaffold is intentionally shipped first so CI can
gate on it once the repos are wired.

---

## Architecture notes

- UITest bundle (`BizarreCRMUITests`) is separate from the unit test bundle
  (`BizarreCRMTests`) per `agent-ownership.md` rule 8.
- No third-party profiler SDKs — metrics come from `XCTest`, `XCTOSSignpostMetric`,
  and the Mach kernel API (`mach_task_basic_info`). All ship with Xcode / Darwin.
- All test classes conform to Swift 6 `Sendable` via `XCTestCase` inheritance.
- `MemoryProbe` uses `#if canImport(Darwin)` so the Core package compiles on
  Linux CI without modification.
