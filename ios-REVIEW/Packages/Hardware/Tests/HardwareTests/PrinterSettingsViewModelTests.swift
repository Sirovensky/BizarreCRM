#if canImport(UIKit)
import XCTest
@testable import Hardware

// MARK: - PrinterSettingsViewModelTests
//
// Tests the pure-logic layer of `PrinterSettingsViewModel`:
//   - `remove(_:)`              — removes the correct persisted printer
//   - `setAsDefaultReceipt(_:)` — flips flags correctly (exactly one default)
//   - `setAsDefaultLabel(_:)`   — flips flags correctly
//   - `defaultReceiptPrinter`   — computed property returns correct printer
//   - `defaultLabelPrinter`     — computed property returns correct printer
//   - `addNetworkPrinter()`     — rejects blank host with an error message
//   - `PersistedPrinter.asPrinter` — mapping helper
//
// The network / AirPrint interaction tests are skipped here; they require a
// live socket (network) or UIViewController (AirPrint) and belong in
// integration tests.

@MainActor
final class PrinterSettingsViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makePrinter(
        id: String = UUID().uuidString,
        name: String = "Test Printer",
        kind: PrinterKind = .thermalReceipt,
        connection: PrinterConnection = .network(host: "10.0.0.1", port: 9100),
        isDefaultReceipt: Bool = false,
        isDefaultLabel: Bool = false
    ) -> PersistedPrinter {
        PersistedPrinter(
            id: id,
            name: name,
            kind: kind,
            connection: connection,
            isDefaultReceipt: isDefaultReceipt,
            isDefaultLabel: isDefaultLabel
        )
    }

    // Inject printers directly via UserDefaults so the ViewModel loads them.
    private func seedDefaults(_ printers: [PersistedPrinter]) {
        guard let data = try? JSONEncoder().encode(printers) else { return }
        UserDefaults.standard.set(data, forKey: "com.bizarrecrm.hardware.printers")
    }

    private func clearDefaults() {
        UserDefaults.standard.removeObject(forKey: "com.bizarrecrm.hardware.printers")
    }

    override func setUp() {
        super.setUp()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        super.tearDown()
    }

    // MARK: - Initial state

    func test_initialState_printersEmpty_whenNoDefaultsSet() {
        let vm = PrinterSettingsViewModel()
        XCTAssertTrue(vm.printers.isEmpty)
    }

    func test_initialState_loadsFromDefaults() {
        let p = makePrinter(id: "p1", name: "My Printer")
        seedDefaults([p])
        let vm = PrinterSettingsViewModel()
        XCTAssertEqual(vm.printers.count, 1)
        XCTAssertEqual(vm.printers.first?.name, "My Printer")
    }

    // MARK: - remove

    func test_remove_removesCorrectPrinter() {
        let p1 = makePrinter(id: "p1", name: "A")
        let p2 = makePrinter(id: "p2", name: "B")
        seedDefaults([p1, p2])
        let vm = PrinterSettingsViewModel()

        vm.remove(p1)

        XCTAssertEqual(vm.printers.count, 1)
        XCTAssertEqual(vm.printers.first?.id, "p2")
    }

    func test_remove_nonExistentPrinter_doesNotCrash() {
        let p = makePrinter(id: "p1")
        seedDefaults([p])
        let vm = PrinterSettingsViewModel()
        let ghost = makePrinter(id: "ghost")

        vm.remove(ghost)

        XCTAssertEqual(vm.printers.count, 1,
                       "Removing a non-existent printer must leave the list unchanged")
    }

    func test_remove_singlePrinter_leavesEmptyList() {
        let p = makePrinter(id: "only")
        seedDefaults([p])
        let vm = PrinterSettingsViewModel()

        vm.remove(p)

        XCTAssertTrue(vm.printers.isEmpty)
    }

    // MARK: - setAsDefaultReceipt

    func test_setAsDefaultReceipt_marksOnlyTargetPrinter() {
        let p1 = makePrinter(id: "p1", name: "A")
        let p2 = makePrinter(id: "p2", name: "B")
        seedDefaults([p1, p2])
        let vm = PrinterSettingsViewModel()

        vm.setAsDefaultReceipt(p2)

        XCTAssertFalse(vm.printers.first(where: { $0.id == "p1" })?.isDefaultReceipt ?? true,
                       "p1 must NOT be default receipt after setting p2")
        XCTAssertTrue(vm.printers.first(where: { $0.id == "p2" })?.isDefaultReceipt ?? false,
                      "p2 must be default receipt")
    }

    func test_setAsDefaultReceipt_clearsOldDefault() {
        let p1 = makePrinter(id: "p1", isDefaultReceipt: true)
        let p2 = makePrinter(id: "p2")
        seedDefaults([p1, p2])
        let vm = PrinterSettingsViewModel()

        vm.setAsDefaultReceipt(p2)

        XCTAssertFalse(vm.printers.first(where: { $0.id == "p1" })?.isDefaultReceipt ?? true,
                       "Old default must be cleared when a new one is set")
        XCTAssertTrue(vm.printers.first(where: { $0.id == "p2" })?.isDefaultReceipt ?? false)
    }

    func test_setAsDefaultReceipt_exactlyOneDefault_afterMultipleCalls() {
        let p1 = makePrinter(id: "p1")
        let p2 = makePrinter(id: "p2")
        let p3 = makePrinter(id: "p3")
        seedDefaults([p1, p2, p3])
        let vm = PrinterSettingsViewModel()

        vm.setAsDefaultReceipt(p1)
        vm.setAsDefaultReceipt(p3)

        let defaults = vm.printers.filter { $0.isDefaultReceipt }
        XCTAssertEqual(defaults.count, 1, "Exactly one printer must be default receipt")
        XCTAssertEqual(defaults.first?.id, "p3")
    }

    // MARK: - setAsDefaultLabel

    func test_setAsDefaultLabel_marksOnlyTargetPrinter() {
        let p1 = makePrinter(id: "p1")
        let p2 = makePrinter(id: "p2")
        seedDefaults([p1, p2])
        let vm = PrinterSettingsViewModel()

        vm.setAsDefaultLabel(p1)

        XCTAssertTrue(vm.printers.first(where: { $0.id == "p1" })?.isDefaultLabel ?? false)
        XCTAssertFalse(vm.printers.first(where: { $0.id == "p2" })?.isDefaultLabel ?? true)
    }

    func test_setAsDefaultLabel_independentFromReceiptDefault() {
        let p1 = makePrinter(id: "p1", isDefaultReceipt: true)
        let p2 = makePrinter(id: "p2")
        seedDefaults([p1, p2])
        let vm = PrinterSettingsViewModel()

        vm.setAsDefaultLabel(p2)

        // p1 keeps its receipt default
        XCTAssertTrue(vm.printers.first(where: { $0.id == "p1" })?.isDefaultReceipt ?? false,
                      "setAsDefaultLabel must not affect isDefaultReceipt flags")
        // p2 has label default
        XCTAssertTrue(vm.printers.first(where: { $0.id == "p2" })?.isDefaultLabel ?? false)
    }

    // MARK: - defaultReceiptPrinter / defaultLabelPrinter

    func test_defaultReceiptPrinter_returnsCorrectPrinter() {
        let p1 = makePrinter(id: "p1", name: "Receipt Printer", isDefaultReceipt: true)
        let p2 = makePrinter(id: "p2", name: "Other")
        seedDefaults([p1, p2])
        let vm = PrinterSettingsViewModel()

        XCTAssertEqual(vm.defaultReceiptPrinter?.id, "p1")
    }

    func test_defaultReceiptPrinter_nilWhenNoneSet() {
        let p1 = makePrinter(id: "p1")
        seedDefaults([p1])
        let vm = PrinterSettingsViewModel()
        XCTAssertNil(vm.defaultReceiptPrinter)
    }

    func test_defaultLabelPrinter_returnsCorrectPrinter() {
        let p1 = makePrinter(id: "p1")
        let p2 = makePrinter(id: "p2", name: "Label", isDefaultLabel: true)
        seedDefaults([p1, p2])
        let vm = PrinterSettingsViewModel()

        XCTAssertEqual(vm.defaultLabelPrinter?.id, "p2")
    }

    func test_defaultLabelPrinter_nilWhenNoneSet() {
        let p1 = makePrinter(id: "p1")
        seedDefaults([p1])
        let vm = PrinterSettingsViewModel()
        XCTAssertNil(vm.defaultLabelPrinter)
    }

    // MARK: - addNetworkPrinter validation

    func test_addNetworkPrinter_emptyHost_setsErrorMessage() async {
        let vm = PrinterSettingsViewModel()
        vm.newPrinterHost = ""
        vm.newPrinterPort = "9100"

        await vm.addNetworkPrinter()

        XCTAssertNotNil(vm.errorMessage,
                        "Blank host must produce an error message")
        XCTAssertTrue(vm.printers.isEmpty,
                      "No printer must be added when host is blank")
    }

    func test_addNetworkPrinter_whitespaceOnlyHost_setsErrorMessage() async {
        let vm = PrinterSettingsViewModel()
        vm.newPrinterHost = "   "

        await vm.addNetworkPrinter()

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - newPrinter form field defaults

    func test_newPrinterPort_defaultIs9100() {
        let vm = PrinterSettingsViewModel()
        XCTAssertEqual(vm.newPrinterPort, "9100")
    }

    func test_newPrinterHost_defaultIsEmpty() {
        let vm = PrinterSettingsViewModel()
        XCTAssertTrue(vm.newPrinterHost.isEmpty)
    }

    // MARK: - PersistedPrinter.asPrinter mapping

    func test_asPrinter_preservesId() {
        let persisted = makePrinter(id: "stable-id", name: "Mapped")
        let printer = persisted.asPrinter
        XCTAssertEqual(printer.id, "stable-id")
        XCTAssertEqual(printer.name, "Mapped")
    }

    func test_asPrinter_preservesConnection() {
        let persisted = makePrinter(
            id: "p1",
            connection: .network(host: "1.2.3.4", port: 1234)
        )
        let printer = persisted.asPrinter
        if case .network(let host, let port) = printer.connection {
            XCTAssertEqual(host, "1.2.3.4")
            XCTAssertEqual(port, 1234)
        } else {
            XCTFail("Connection type must be preserved by asPrinter")
        }
    }

    // MARK: - PersistedPrinter Codable round-trip

    func test_persistedPrinter_roundTripJSON() throws {
        let original = makePrinter(
            id: "json-round-trip",
            name: "JSON Printer",
            kind: .label,
            connection: .airPrint(url: URL(string: "ipp://printer.local/ipp/print")!),
            isDefaultReceipt: true,
            isDefaultLabel: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedPrinter.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.kind, original.kind)
        XCTAssertEqual(decoded.isDefaultReceipt, original.isDefaultReceipt)
        XCTAssertEqual(decoded.isDefaultLabel, original.isDefaultLabel)
    }

    func test_persistedPrinter_networkConnection_roundTripJSON() throws {
        let original = makePrinter(
            id: "net",
            connection: .network(host: "192.168.99.99", port: 9100)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedPrinter.self, from: data)

        if case .network(let host, let port) = decoded.connection {
            XCTAssertEqual(host, "192.168.99.99")
            XCTAssertEqual(port, 9100)
        } else {
            XCTFail("Network connection must survive JSON round-trip")
        }
    }
}
#endif
