# iOS Performance Benchmark Harness

Scroll-fps benchmark suite for the Phase 3 gate requirement:
**Every list scrolls 1000 rows at 60 fps minimum.**

---

## Running the benchmarks

```bash
bash ios/scripts/bench.sh
```

This runs all five `*ScrollTests` classes via `xcodebuild` against an
iPhone 15 simulator and writes results to `/tmp/ios-perf.xcresult`.

Open that bundle in Xcode (File → Open) to see per-iteration graphs for
each `XCTOSSignpostMetric` and `XCTClockMetric`.

---

## Interpreting metrics

| Metric | Source | Pass criterion |
|---|---|---|
| Scroll deceleration duration | `XCTOSSignpostMetric.scrollDecelerationMetric` | p95 < 16.67 ms |
| Navigation transition duration | `XCTOSSignpostMetric.navigationTransitionMetric` | p95 < 300 ms |
| Wall-clock time per iteration | `XCTClockMetric` | informational |

**Frame time math:**

- 60 fps → 1000 ms / 60 = **16.67 ms** per frame (iPhone SE minimum)
- 120 fps → 1000 ms / 120 = **8.33 ms** per frame (iPad Pro M-series ProMotion target)

A p95 scroll deceleration metric above 16.67 ms indicates dropped frames and
means the Phase 3 gate is **not met**.

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
    // Swap domain repositories with mock implementations returning 1000 rows.
    Container.shared.ticketRepository.register { MockTicketRepository(rowCount: 1000) }
    Container.shared.customerRepository.register { MockCustomerRepository(rowCount: 1000) }
    Container.shared.inventoryRepository.register { MockInventoryRepository(rowCount: 1000) }
    Container.shared.invoiceRepository.register { MockInvoiceRepository(rowCount: 1000) }
    Container.shared.communicationsRepository.register { MockCommunicationsRepository(rowCount: 1000) }
}
```

Each `Mock*Repository` should return `rowCount` lightweight structs with
stable, deterministic IDs so SwiftUI's diffing is fast and `EquatableView`
wrappers fire correctly.

**TODO checklist for the follow-up PR:**

- [ ] Add `MockTicketRepository` in `Packages/Tickets/Sources/Tickets/Mocks/`
- [ ] Add `MockCustomerRepository` in `Packages/Customers/Sources/Customers/Mocks/`
- [ ] Add `MockInventoryRepository` in `Packages/Inventory/Sources/Inventory/Mocks/`
- [ ] Add `MockInvoiceRepository` in `Packages/Invoices/Sources/Invoices/Mocks/`
- [ ] Add `MockCommunicationsRepository` in `Packages/Communications/Sources/Communications/Mocks/`
- [ ] Wire all five into `AppServices.swift` under the `-PerformanceHarness` guard
- [ ] Re-run `bash ios/scripts/bench.sh` and confirm green gate

Until this wiring lands, `bench.sh` will fail (the app launches but lists are
empty, causing XCUITest element lookups to time out). This is expected and
documented — the harness scaffold is intentionally shipped first so CI can
gate on it once the repos are wired.

---

## Architecture notes

- UITest bundle (`BizarreCRMUITests`) is separate from the unit test bundle
  (`BizarreCRMTests`) per `agent-ownership.md` rule 8.
- No third-party SDKs — metrics come from `XCTest` and `XCTOSSignpostMetric`
  which ship with Xcode.
- All test classes conform to Swift 6 `Sendable` via `XCTestCase` inheritance
  (no additional `@Sendable` annotations needed for the test methods themselves).
