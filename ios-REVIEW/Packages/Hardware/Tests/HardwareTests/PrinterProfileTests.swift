import XCTest
@testable import Hardware

// §17.4 — PrinterProfile + PrintMediumPreference tests

final class PrinterProfileTests: XCTestCase {

    // MARK: - PrinterProfile serialisation

    func testPrinterProfile_encodesAndDecodes() throws {
        let profile = PrinterProfile(
            stationId: "test-station-uuid",
            stationName: "Front Counter",
            locationId: "loc-001",
            defaultReceiptPrinterId: "printer-001",
            defaultLabelPrinterId: nil,
            paperSize: .thermal80mm
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(PrinterProfile.self, from: data)

        XCTAssertEqual(decoded.stationId, profile.stationId)
        XCTAssertEqual(decoded.stationName, profile.stationName)
        XCTAssertEqual(decoded.locationId, profile.locationId)
        XCTAssertEqual(decoded.defaultReceiptPrinterId, profile.defaultReceiptPrinterId)
        XCTAssertNil(decoded.defaultLabelPrinterId)
        XCTAssertEqual(decoded.paperSize, .thermal80mm)
    }

    // MARK: - PrintMediumPreference → PrintMedium mapping

    func testPrintMediumPreference_allCasesMapToPrintMedium() {
        for preference in PrintMediumPreference.allCases {
            let medium = preference.printMedium
            XCTAssertNotNil(medium, "Preference \(preference.rawValue) must map to a valid PrintMedium")
        }
    }

    func testPrintMediumPreference_thermal80mm() {
        let medium = PrintMediumPreference.thermal80mm.printMedium
        XCTAssertEqual(medium, .thermal80mm)
    }

    func testPrintMediumPreference_letter() {
        let medium = PrintMediumPreference.letter.printMedium
        XCTAssertEqual(medium, .letter)
    }

    func testPrintMediumPreference_legal() {
        let medium = PrintMediumPreference.legal.printMedium
        XCTAssertEqual(medium, .legal)
    }

    func testPrintMediumPreference_allCasesCount() {
        // Verify all 6 paper sizes are present: thermal80mm, thermal58mm, letter, legal, a4, label2x4
        XCTAssertEqual(PrintMediumPreference.allCases.count, 6)
    }

    // MARK: - PersistedJobEntry serialisation

    func testPersistedJobEntry_encodesAndDecodes() throws {
        let entry = PersistedJobEntry(
            jobId: UUID(),
            jobKind: "receipt",
            payloadData: Data("payload".utf8),
            payloadKind: "receipt",
            printerData: Data("printer".utf8),
            attempts: 2,
            lastError: "Timeout",
            deadLettered: false
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(PersistedJobEntry.self, from: data)

        XCTAssertEqual(decoded.jobId, entry.jobId)
        XCTAssertEqual(decoded.jobKind, entry.jobKind)
        XCTAssertEqual(decoded.attempts, 2)
        XCTAssertEqual(decoded.lastError, "Timeout")
        XCTAssertFalse(decoded.deadLettered)
    }

    // MARK: - TipOption

    func testTipOption_standardOptions_zeroForNoTip() {
        let options = TipOption.standard(totalCents: 1000)
        let noTip = options.first { $0.label == "No Tip" }
        XCTAssertNotNil(noTip)
        XCTAssertEqual(noTip?.amountCents, 0)
    }

    func testTipOption_standardOptions_calculatesPercentages() {
        let options = TipOption.standard(totalCents: 10000)  // $100.00
        let tip20 = options.first { $0.label == "20%" }
        XCTAssertNotNil(tip20)
        XCTAssertEqual(tip20?.amountCents, 2000)  // 20% of $100 = $20.00
    }

    func testTipOption_identifiable() {
        let o1 = TipOption(id: "t1", label: "15%", amountCents: 150)
        let o2 = TipOption(id: "t2", label: "20%", amountCents: 200)
        XCTAssertNotEqual(o1.id, o2.id)
    }
}
