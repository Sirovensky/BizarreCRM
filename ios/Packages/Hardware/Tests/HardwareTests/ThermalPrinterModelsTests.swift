import XCTest
@testable import Hardware

// MARK: - ThermalPrinterModelsTests
//
// Tests for §17.4 "Models targeted" — ThermalPrinterModelRegistry.

final class ThermalPrinterModelsTests: XCTestCase {

    // MARK: - Registry completeness

    func test_supportedModels_countIsFour() {
        XCTAssertEqual(ThermalPrinterModelRegistry.supported.count, 4,
                       "Registry must contain exactly 4 target models (TSP100IV, mPOP, TM-m30II, TM-T88VII)")
    }

    func test_supportedModels_containsStarTSP100IV() {
        let spec = ThermalPrinterModelRegistry.starTSP100IV
        XCTAssertEqual(spec.vendor, .star)
        XCTAssertEqual(spec.paperWidth, .mm80)
        XCTAssertTrue(spec.transports.contains(.usb))
        XCTAssertTrue(spec.transports.contains(.network))
        XCTAssertTrue(spec.transports.contains(.bluetooth))
        XCTAssertTrue(spec.transports.contains(.airPrint))
        XCTAssertTrue(spec.hasDrawerPort)
        XCTAssertFalse(spec.hasIntegratedScanner)
    }

    func test_supportedModels_containsStarMPOP() {
        let spec = ThermalPrinterModelRegistry.starMPOP
        XCTAssertEqual(spec.vendor, .star)
        XCTAssertEqual(spec.paperWidth, .mm58)
        XCTAssertTrue(spec.hasIntegratedScanner, "mPOP has an integrated scanner")
        XCTAssertFalse(spec.transports.contains(.airPrint), "mPOP does not support AirPrint")
    }

    func test_supportedModels_containsEpsonTMm30II() {
        let spec = ThermalPrinterModelRegistry.epsonTMm30II
        XCTAssertEqual(spec.vendor, .epson)
        XCTAssertEqual(spec.paperWidth, .mm80)
        XCTAssertTrue(spec.hasDrawerPort)
        XCTAssertEqual(spec.usbVendorID, 0x04B8, "Epson USB VID must be 0x04B8")
    }

    func test_supportedModels_containsEpsonTMT88VII() {
        let spec = ThermalPrinterModelRegistry.epsonTMT88VII
        XCTAssertEqual(spec.vendor, .epson)
        XCTAssertEqual(spec.paperWidth, .mm80)
        XCTAssertTrue(spec.supportsFullCut)
    }

    // MARK: - Lookup by name

    func test_specForDiscoveredName_matchesStarTSP() {
        let spec = ThermalPrinterModelRegistry.spec(forDiscoveredName: "Star TSP100IV - Wi-Fi")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.vendor, .star)
    }

    func test_specForDiscoveredName_matchesEpsonTM() {
        let spec = ThermalPrinterModelRegistry.spec(forDiscoveredName: "EPSON TM-m30II (001)")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.vendor, .epson)
    }

    func test_specForDiscoveredName_returnsNilForUnknownModel() {
        let spec = ThermalPrinterModelRegistry.spec(forDiscoveredName: "HP LaserJet Pro")
        XCTAssertNil(spec)
    }

    func test_specForDiscoveredName_caseInsensitive() {
        let spec = ThermalPrinterModelRegistry.spec(forDiscoveredName: "star mpop")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.modelName, "Star mPOP")
    }

    // MARK: - PrintMedium mapping

    func test_paperWidth_mm80_mapsToPrintMediumThermal80mm() {
        XCTAssertEqual(ThermalPaperWidth.mm80.printMediumName, "thermal80mm")
    }

    func test_paperWidth_mm58_mapsToPrintMediumThermal58mm() {
        XCTAssertEqual(ThermalPaperWidth.mm58.printMediumName, "thermal58mm")
    }

    // MARK: - Transport options

    func test_thermalTransport_optionSet_combination() {
        let combined: ThermalTransport = [.usb, .network]
        XCTAssertTrue(combined.contains(.usb))
        XCTAssertTrue(combined.contains(.network))
        XCTAssertFalse(combined.contains(.bluetooth))
        XCTAssertFalse(combined.contains(.airPrint))
    }

    // MARK: - All specs are unique by modelName

    func test_allModelNames_areUnique() {
        let names = ThermalPrinterModelRegistry.supported.map { $0.modelName }
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "All model names must be unique")
    }
}
