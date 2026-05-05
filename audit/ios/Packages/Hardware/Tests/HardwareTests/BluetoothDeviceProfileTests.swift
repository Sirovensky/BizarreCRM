import XCTest
import CoreBluetooth
@testable import Hardware

final class BluetoothDeviceProfileTests: XCTestCase {

    // MARK: - Weight scale

    func test_kind_weightScaleSIG_returnsScale() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "181D")])
        XCTAssertEqual(kind, .scale)
    }

    func test_kind_weightScaleFullUUID_returnsScale() {
        // Some peripherals advertise the 128-bit expanded form.
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "0000181D-0000-1000-8000-00805F9B34FB")])
        XCTAssertEqual(kind, .scale)
    }

    // MARK: - Ingenico card reader

    func test_kind_ingenicoUUID_returnsCardReader() {
        let kind = BluetoothDeviceProfile.kind(for: [BluetoothDeviceProfile.ingenicoCardReader])
        XCTAssertEqual(kind, .cardReader)
    }

    // MARK: - APG drawer

    func test_kind_apgDrawerUUID_returnsDrawer() {
        let kind = BluetoothDeviceProfile.kind(for: [BluetoothDeviceProfile.apgDrawerService])
        XCTAssertEqual(kind, .drawer)
    }

    // MARK: - SPP disambiguation by name

    func test_kind_sppSocketMobileName_returnsScanner() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "1101")], name: "Socket CHS 7Ci")
        XCTAssertEqual(kind, .scanner)
    }

    func test_kind_sppCHSName_returnsScanner() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "1101")], name: "CHS 7Ci")
        XCTAssertEqual(kind, .scanner)
    }

    func test_kind_sppStarName_returnsReceiptPrinter() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "1101")], name: "Star TSP100IV")
        XCTAssertEqual(kind, .receiptPrinter)
    }

    func test_kind_sppBSCName_returnsReceiptPrinter() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "1101")], name: "BSC10U")
        XCTAssertEqual(kind, .receiptPrinter)
    }

    func test_kind_sppMPOPName_returnsReceiptPrinter() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "1101")], name: "mPOP")
        XCTAssertEqual(kind, .receiptPrinter)
    }

    func test_kind_sppAPGName_returnsDrawer() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "1101")], name: "APG Vasario")
        XCTAssertEqual(kind, .drawer)
    }

    func test_kind_sppUnknownName_returnsUnknown() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "1101")], name: "Mysterious Device")
        XCTAssertEqual(kind, .unknown)
    }

    // MARK: - No matching UUID

    func test_kind_unknownUUID_returnsNil() {
        let kind = BluetoothDeviceProfile.kind(for: [CBUUID(string: "DEAD")])
        XCTAssertNil(kind)
    }

    func test_kind_emptyServices_returnsNil() {
        let kind = BluetoothDeviceProfile.kind(for: [])
        XCTAssertNil(kind)
    }

    // MARK: - Priority ordering

    func test_kind_scaleBeatsIngenico_whenBothPresent() {
        // scale UUID takes priority over card reader UUID in the resolver
        let kind = BluetoothDeviceProfile.kind(
            for: [BluetoothDeviceProfile.weightScaleService, BluetoothDeviceProfile.ingenicoCardReader]
        )
        XCTAssertEqual(kind, .scale)
    }

    // MARK: - Scan UUIDs

    func test_scanServiceUUIDs_containsWeightScale() {
        XCTAssertTrue(BluetoothDeviceProfile.scanServiceUUIDs.contains(BluetoothDeviceProfile.weightScaleService))
    }

    func test_scanServiceUUIDs_containsSPP() {
        XCTAssertTrue(BluetoothDeviceProfile.scanServiceUUIDs.contains(CBUUID(string: "1101")))
    }
}
