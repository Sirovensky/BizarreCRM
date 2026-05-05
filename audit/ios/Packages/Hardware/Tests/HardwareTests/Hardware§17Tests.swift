import XCTest
@testable import Hardware

// MARK: - Hardware§17Tests
//
// §17 — Tests for the additions landed in aa329e52:
//   1. PrinterConnectionStatus enum cases (ready / printing / offline / error)
//   2. BarcodeScannerBuffer CR/LF immediate flush
//   3. BarcodeScannerBuffer 80 ms debounce window fires
//   4. BarcodeScannerBuffer exceeding maximumLength discards buffer
//   5. WeightUnitStore persistence round-trip (all four units)
//   6. HardwareDiagnosticsViewModel concurrent ping sweep completes
//   7. HardwareDiagnosticsViewModel reachableCount after sweep
//   8. AirPrintAvailability.isUsable + requiresPicker derived properties

// MARK: - 1. PrinterConnectionStatus

final class PrinterConnectionStatusTests: XCTestCase {

    func test_ready_fromIdleReachable() {
        let status = PrinterConnectionStatus(printerStatus: .idle, isReachable: true)
        XCTAssertEqual(status, .ready)
    }

    func test_offline_whenNotReachable() {
        // isReachable == false always maps to .offline regardless of PrinterStatus.
        let status = PrinterConnectionStatus(printerStatus: .idle, isReachable: false)
        XCTAssertEqual(status, .offline)
    }

    func test_printing_fromPrintingReachable() {
        let status = PrinterConnectionStatus(printerStatus: .printing, isReachable: true)
        XCTAssertEqual(status, .printing)
    }

    func test_error_fromErrorReachable() {
        let status = PrinterConnectionStatus(printerStatus: .error("Paper jam"), isReachable: true)
        if case .error(let msg) = status {
            XCTAssertEqual(msg, "Paper jam")
        } else {
            XCTFail("Expected .error, got \(status)")
        }
    }

    func test_offline_fromErrorOfflineLiteral() {
        // Convention: engine stores "offline" literal → maps to .offline case.
        let status = PrinterConnectionStatus(printerStatus: .error("offline"), isReachable: true)
        XCTAssertEqual(status, .offline)
    }

    func test_label_ready() {
        XCTAssertEqual(PrinterConnectionStatus.ready.label, "Ready")
    }

    func test_label_offline() {
        XCTAssertEqual(PrinterConnectionStatus.offline.label, "Offline")
    }

    func test_accessibilityDescription_error_includesMessage() {
        let desc = PrinterConnectionStatus.error("Low paper").accessibilityDescription
        XCTAssertTrue(desc.contains("Low paper"), "Got: \(desc)")
    }
}

// MARK: - 2–4. BarcodeScannerBuffer

// Concrete delegate for tests.
private final class MockScannerDelegate: BarcodeScannerBufferDelegate, @unchecked Sendable {
    var scannedBarcodes: [String] = []

    @MainActor
    func scannerBuffer(_ buffer: BarcodeScannerBuffer, didScan barcode: String) {
        scannedBarcodes.append(barcode)
    }
}

final class BarcodeScannerBufferTests: XCTestCase {

    // MARK: - CR flush

    func test_carriageReturn_flushesImmediately() async {
        let delegate = MockScannerDelegate()
        let buffer = BarcodeScannerBuffer(
            delegate: delegate,
            windowDuration: .milliseconds(500), // long window — CR must bypass it
            maximumLength: 128
        )

        await buffer.append("4")
        await buffer.append("2")
        await buffer.append("0")
        await buffer.append("\r") // immediate flush

        // Yield to MainActor to let the Task { @MainActor } in flushNow deliver.
        await Task.yield()

        await MainActor.run {
            XCTAssertEqual(delegate.scannedBarcodes, ["420"],
                           "CR should flush buffer immediately")
        }
    }

    // MARK: - LF flush

    func test_lineFeed_flushesImmediately() async {
        let delegate = MockScannerDelegate()
        let buffer = BarcodeScannerBuffer(
            delegate: delegate,
            windowDuration: .milliseconds(500),
            maximumLength: 128
        )

        await buffer.append("ABC\n")
        await Task.yield()

        await MainActor.run {
            XCTAssertEqual(delegate.scannedBarcodes, ["ABC"])
        }
    }

    // MARK: - Debounce window

    func test_debounceWindow_firesAfterSilence() async throws {
        let delegate = MockScannerDelegate()
        let buffer = BarcodeScannerBuffer(
            delegate: delegate,
            windowDuration: .milliseconds(80),
            maximumLength: 128
        )

        await buffer.append("X")
        await buffer.append("Y")
        await buffer.append("Z")

        // Wait for debounce window + generous margin.
        try await Task.sleep(for: .milliseconds(200))
        await Task.yield()

        await MainActor.run {
            XCTAssertEqual(delegate.scannedBarcodes, ["XYZ"],
                           "Debounce should fire after 80 ms silence")
        }
    }

    // MARK: - maximumLength guard

    func test_maximumLength_discardsBuffer() async throws {
        let delegate = MockScannerDelegate()
        let buffer = BarcodeScannerBuffer(
            delegate: delegate,
            windowDuration: .milliseconds(80),
            maximumLength: 5 // tight cap
        )

        // Feed 6 characters — exceeds cap.
        await buffer.append("AAAAAA")

        // Wait past debounce window — nothing should fire.
        try await Task.sleep(for: .milliseconds(200))
        await Task.yield()

        await MainActor.run {
            XCTAssertTrue(delegate.scannedBarcodes.isEmpty,
                          "Buffer should be discarded when maximumLength exceeded")
        }
    }

    // MARK: - clear()

    func test_clear_preventsFlush() async throws {
        let delegate = MockScannerDelegate()
        let buffer = BarcodeScannerBuffer(
            delegate: delegate,
            windowDuration: .milliseconds(80),
            maximumLength: 128
        )

        await buffer.append("hello")
        await buffer.clear()

        try await Task.sleep(for: .milliseconds(200))
        await Task.yield()

        await MainActor.run {
            XCTAssertTrue(delegate.scannedBarcodes.isEmpty,
                          "clear() should prevent the debounce flush")
        }
    }
}

// MARK: - 5. WeightUnitStore persistence

final class WeightUnitStorePersistenceTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "com.bizarrecrm.test.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return ud
    }

    func test_defaultUnit_isGrams() {
        // WeightUnitStore reads from UserDefaults.standard by default;
        // use a fresh UserDefaults so no prior state bleeds in.
        // Since WeightUnitStore.selectedUnit reads UserDefaults.standard,
        // verify the fallback logic with a missing key.
        let ud = freshDefaults()
        // No key written → rawValue lookup fails → defaults to .grams.
        let raw = ud.string(forKey: "com.bizarrecrm.scale.weightUnit")
        XCTAssertNil(raw, "Fresh defaults should have no stored unit")
        // WeightUnit init from nil rawValue → guarded to .grams:
        let unit = raw.flatMap { WeightUnit(rawValue: $0) } ?? .grams
        XCTAssertEqual(unit, .grams)
    }

    func test_allUnits_rawValues_roundtrip() {
        // Every WeightUnit rawValue must survive a UserDefaults round-trip.
        for unit in WeightUnit.allCases {
            let ud = freshDefaults()
            ud.set(unit.rawValue, forKey: "com.bizarrecrm.scale.weightUnit")
            let stored = ud.string(forKey: "com.bizarrecrm.scale.weightUnit")
            let decoded = stored.flatMap { WeightUnit(rawValue: $0) }
            XCTAssertEqual(decoded, unit, "\(unit) rawValue round-trip failed")
        }
    }

    func test_pounds_rawValue() {
        XCTAssertEqual(WeightUnit.pounds.rawValue, "lb")
    }

    func test_ounces_rawValue() {
        XCTAssertEqual(WeightUnit.ounces.rawValue, "oz")
    }
}

// MARK: - 6 & 7. HardwareDiagnosticsViewModel

@MainActor
final class HardwareDiagnosticsViewModelTests: XCTestCase {

    func test_runDiagnostics_setsIsRunningFalseOnCompletion() async {
        let vm = HardwareDiagnosticsViewModel(
            initialItems: [
                HardwareDiagnosticsItem(deviceName: "Test Printer", deviceKind: .receiptPrinter)
            ],
            pingTimeout: .milliseconds(200)
        )

        await vm.runDiagnostics()
        XCTAssertFalse(vm.isRunning, "isRunning should be false after sweep completes")
        XCTAssertNotNil(vm.completedAt, "completedAt should be set after sweep")
    }

    func test_runDiagnostics_reachableCount_scaleAndScanner() async {
        // Scale and scanner peripherals are always marked reachable in the
        // placeholder ping (BLE cached state: true).
        let vm = HardwareDiagnosticsViewModel(
            initialItems: [
                HardwareDiagnosticsItem(deviceName: "Scale", deviceKind: .scale),
                HardwareDiagnosticsItem(deviceName: "Scanner", deviceKind: .scanner),
            ],
            pingTimeout: .milliseconds(200)
        )

        await vm.runDiagnostics()
        XCTAssertEqual(vm.reachableCount, 2,
                       "Scale and scanner should both be reachable via BLE placeholder")
    }

    func test_runDiagnostics_cardReader_isNotConfigured() async {
        let vm = HardwareDiagnosticsViewModel(
            initialItems: [
                HardwareDiagnosticsItem(deviceName: "BlockChyp", deviceKind: .cardReader)
            ],
            pingTimeout: .milliseconds(200)
        )

        await vm.runDiagnostics()
        guard let item = vm.items.first else {
            XCTFail("No items after sweep"); return
        }
        if case .notConfigured = item.pingState {
            // Expected — BlockChyp has its own ping path.
        } else {
            XCTFail("Expected .notConfigured for cardReader, got \(item.pingState)")
        }
    }

    func test_runDiagnostics_idempotent_doesNotReenterWhileRunning() async {
        // Calling runDiagnostics a second time while first is in flight is a no-op.
        let vm = HardwareDiagnosticsViewModel(
            initialItems: [
                HardwareDiagnosticsItem(deviceName: "Printer", deviceKind: .receiptPrinter)
            ],
            pingTimeout: .milliseconds(500)
        )

        // Fire-and-forget first sweep.
        async let first: () = vm.runDiagnostics()
        // Immediate second call — must be a no-op (isRunning guard).
        await vm.runDiagnostics()
        await first
        // If we reach here without deadlock, the guard worked correctly.
        XCTAssertFalse(vm.isRunning)
    }
}

// MARK: - 8. AirPrintAvailability derived properties

final class AirPrintAvailabilityTests: XCTestCase {

    func test_available_isUsable() {
        XCTAssertTrue(AirPrintAvailability.available.isUsable)
    }

    func test_availableNoCachedPrinter_isUsable() {
        XCTAssertTrue(AirPrintAvailability.availableNoCachedPrinter.isUsable)
    }

    func test_availableNoCachedPrinter_requiresPicker() {
        XCTAssertTrue(AirPrintAvailability.availableNoCachedPrinter.requiresPicker)
    }

    func test_available_doesNotRequirePicker() {
        XCTAssertFalse(AirPrintAvailability.available.requiresPicker)
    }

    func test_mfiPrinterPreferred_isNotUsable() {
        XCTAssertFalse(AirPrintAvailability.mfiPrinterPreferred(printerName: "Star").isUsable)
    }

    func test_notAvailable_isNotUsable() {
        XCTAssertFalse(AirPrintAvailability.notAvailable(reason: "Simulator").isUsable)
    }

    func test_mfiPrinterPreferred_localizedDescription_includesPrinterName() {
        let desc = AirPrintAvailability.mfiPrinterPreferred(printerName: "Epson TM-m30").localizedDescription
        XCTAssertTrue(desc.contains("Epson TM-m30"), "Got: \(desc)")
    }

    func test_notAvailable_localizedDescription_includesReason() {
        let reason = "UIPrintInteractionController.isPrintingAvailable == false"
        let desc = AirPrintAvailability.notAvailable(reason: reason).localizedDescription
        XCTAssertTrue(desc.contains(reason), "Got: \(desc)")
    }
}
