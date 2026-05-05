import XCTest
@testable import Hardware

final class PeripheralStationProfileTests: XCTestCase {

    // MARK: - PeripheralStationProfile

    func test_defaultProfile_noPrinterIsPdfFallback() {
        let profile = PeripheralStationProfile(name: "Counter 1")
        XCTAssertTrue(profile.usesPdfFallback)
    }

    func test_profileWithPrinter_notPdfFallback() {
        let profile = PeripheralStationProfile(name: "Counter 1", receiptPrinterSerial: "SN12345")
        XCTAssertFalse(profile.usesPdfFallback)
    }

    func test_noTerminalConfigured() {
        let profile = PeripheralStationProfile(name: "Counter 1")
        XCTAssertTrue(profile.noTerminalConfigured)
    }

    func test_manualDrawerRequired_whenDrawerEnabledButNoPrinter() {
        let profile = PeripheralStationProfile(name: "Counter 1", cashDrawerEnabled: true)
        XCTAssertTrue(profile.manualDrawerRequired)
    }

    func test_manualDrawerNotRequired_whenPrinterPresent() {
        let profile = PeripheralStationProfile(
            name: "Counter 1",
            receiptPrinterSerial: "SN999",
            cashDrawerEnabled: true
        )
        XCTAssertFalse(profile.manualDrawerRequired)
    }

    func test_profile_codable() throws {
        let original = PeripheralStationProfile(
            name: "Front Counter",
            receiptPrinterSerial: "SN001",
            cashDrawerEnabled: true,
            terminalName: "counter-1"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PeripheralStationProfile.self, from: data)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.receiptPrinterSerial, original.receiptPrinterSerial)
        XCTAssertEqual(decoded.cashDrawerEnabled, original.cashDrawerEnabled)
        XCTAssertEqual(decoded.terminalName, original.terminalName)
    }

    // MARK: - StationFallbackHandler

    func test_fallback_noPrinter_pdfShareSheet() {
        let profile = PeripheralStationProfile(name: "Test")
        let handler = StationFallbackHandler(profile: profile)
        XCTAssertEqual(handler.receiptFallback(printerReachable: false), .pdfShareSheet)
        XCTAssertEqual(handler.receiptFallback(printerReachable: true), .pdfShareSheet)
    }

    func test_fallback_withPrinter_printsWhenReachable() {
        let profile = PeripheralStationProfile(name: "Test", receiptPrinterSerial: "SN1")
        let handler = StationFallbackHandler(profile: profile)
        XCTAssertEqual(handler.receiptFallback(printerReachable: true), .printDirect)
        XCTAssertEqual(handler.receiptFallback(printerReachable: false), .pdfShareSheet)
    }

    func test_fallback_noProfile_cashOnly() {
        let handler = StationFallbackHandler(profile: nil)
        XCTAssertEqual(handler.cardFallback(terminalOnline: true), .cashOnly)
    }

    func test_fallback_withTerminal_online() {
        let profile = PeripheralStationProfile(name: "Test", terminalName: "t1")
        let handler = StationFallbackHandler(profile: profile)
        XCTAssertEqual(handler.cardFallback(terminalOnline: true), .useTerminal)
        XCTAssertEqual(handler.cardFallback(terminalOnline: false), .cashOnly)
    }

    func test_fallback_drawerNoPrinter_manualOpen() {
        let profile = PeripheralStationProfile(name: "Test", cashDrawerEnabled: true)
        let handler = StationFallbackHandler(profile: profile)
        XCTAssertEqual(handler.drawerFallback(printerReachable: true), .manualOpenWithAudit)
    }

    func test_fallback_drawerWithPrinterReachable_kick() {
        let profile = PeripheralStationProfile(
            name: "Test",
            receiptPrinterSerial: "SN1",
            cashDrawerEnabled: true
        )
        let handler = StationFallbackHandler(profile: profile)
        XCTAssertEqual(handler.drawerFallback(printerReachable: true), .kickViaPrinter)
        XCTAssertEqual(handler.drawerFallback(printerReachable: false), .manualOpenWithAudit)
    }
}

// MARK: - StationFallbackHandler equatability helpers

extension StationFallbackHandler.ReceiptFallback: Equatable {}
extension StationFallbackHandler.DrawerFallback: Equatable {}
extension StationFallbackHandler.CardFallback: Equatable {}
