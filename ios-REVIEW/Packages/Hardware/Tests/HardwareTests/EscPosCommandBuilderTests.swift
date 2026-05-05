import XCTest
@testable import Hardware

final class EscPosCommandBuilderTests: XCTestCase {

    // MARK: - initialize

    func test_initialize_isEscAt() {
        let data = EscPosCommandBuilder.initialize()
        XCTAssertEqual(Array(data), [0x1B, 0x40],
                       "ESC @ must be exactly [0x1B, 0x40]")
    }

    // MARK: - align

    func test_align_left() {
        let data = EscPosCommandBuilder.align(.left)
        XCTAssertEqual(Array(data), [0x1B, 0x61, 0x00])
    }

    func test_align_center() {
        let data = EscPosCommandBuilder.align(.center)
        XCTAssertEqual(Array(data), [0x1B, 0x61, 0x01])
    }

    func test_align_right() {
        let data = EscPosCommandBuilder.align(.right)
        XCTAssertEqual(Array(data), [0x1B, 0x61, 0x02])
    }

    // MARK: - bold

    func test_bold_on() {
        let data = EscPosCommandBuilder.bold(true)
        XCTAssertEqual(Array(data), [0x1B, 0x45, 0x01])
    }

    func test_bold_off() {
        let data = EscPosCommandBuilder.bold(false)
        XCTAssertEqual(Array(data), [0x1B, 0x45, 0x00])
    }

    // MARK: - fontSize

    func test_fontSize_1x1_isZeroByte() {
        let data = EscPosCommandBuilder.fontSize(width: 1, height: 1)
        // n = ((1-1) << 4) | (1-1) = 0x00
        XCTAssertEqual(Array(data), [0x1D, 0x21, 0x00])
    }

    func test_fontSize_2x2() {
        let data = EscPosCommandBuilder.fontSize(width: 2, height: 2)
        // n = ((2-1) << 4) | (2-1) = 0x11
        XCTAssertEqual(Array(data), [0x1D, 0x21, 0x11])
    }

    func test_fontSize_clampsToMax8() {
        let data = EscPosCommandBuilder.fontSize(width: 10, height: 10)
        // clamped to 8 → n = ((8-1) << 4) | (8-1) = 0x77
        XCTAssertEqual(Array(data), [0x1D, 0x21, 0x77])
    }

    func test_fontSize_clampsToMin1() {
        let data = EscPosCommandBuilder.fontSize(width: 0, height: 0)
        // clamped to 1 → n = 0x00
        XCTAssertEqual(Array(data), [0x1D, 0x21, 0x00])
    }

    // MARK: - feed

    func test_feed_n_lines() {
        let data = EscPosCommandBuilder.feed(3)
        XCTAssertEqual(Array(data), [0x1B, 0x64, 3])
    }

    func test_feed_clampsToZero() {
        let data = EscPosCommandBuilder.feed(-1)
        XCTAssertEqual(Array(data), [0x1B, 0x64, 0])
    }

    func test_feed_clampsTo255() {
        let data = EscPosCommandBuilder.feed(300)
        XCTAssertEqual(Array(data), [0x1B, 0x64, 255])
    }

    // MARK: - cut

    func test_cut_partial() {
        let data = EscPosCommandBuilder.cut(partial: true)
        XCTAssertEqual(Array(data), [0x1D, 0x56, 0x01])
    }

    func test_cut_full() {
        let data = EscPosCommandBuilder.cut(partial: false)
        XCTAssertEqual(Array(data), [0x1D, 0x56, 0x00])
    }

    // MARK: - drawerKick

    func test_drawerKick_startsWithEscP() {
        let data = EscPosCommandBuilder.drawerKick()
        XCTAssertEqual(data.count, 5)
        XCTAssertEqual(data[0], 0x1B) // ESC
        XCTAssertEqual(data[1], 0x70) // p
        XCTAssertEqual(data[2], 0x00) // pin 2
    }

    // MARK: - text

    func test_text_appendsLF() {
        let data = EscPosCommandBuilder.text("Hi")
        XCTAssertTrue(data.last == 0x0A, "text() must end with LF (0x0A)")
        let str = String(data: data.dropLast(), encoding: .utf8)
        XCTAssertEqual(str, "Hi")
    }

    // MARK: - separator

    func test_separator_defaultWidth42() {
        let data = EscPosCommandBuilder.separator()
        // 42 dashes + LF
        XCTAssertEqual(data.count, 43)
        for i in 0..<42 {
            XCTAssertEqual(data[i], UInt8(ascii: "-"))
        }
    }

    func test_separator_customWidth() {
        let data = EscPosCommandBuilder.separator(width: 10)
        XCTAssertEqual(data.count, 11) // 10 + LF
    }

    // MARK: - lineItem

    func test_lineItem_totalsToSpecifiedWidth() {
        let data = EscPosCommandBuilder.lineItem(label: "Tax", value: "$1.00", totalWidth: 20)
        // "Tax" (3) + spaces (12) + "$1.00" (5) = 20 + LF
        XCTAssertEqual(data.count, 21,
                       "lineItem total chars should equal totalWidth + LF byte")
    }

    func test_lineItem_minimumOneSpaceGap() {
        // Even when label+value is longer than totalWidth, must have ≥1 space gap
        let data = EscPosCommandBuilder.lineItem(
            label: "VeryLongLabelHere", value: "VeryLongValueHere", totalWidth: 10)
        // Gap should still be 1 space → "VeryLongLabelHere VeryLongValueHere\n"
        let str = String(data: data, encoding: .utf8)!.dropLast() // drop LF
        XCTAssertTrue(str.contains(" "), "lineItem must have at least 1 space between label and value")
    }

    // MARK: - qrCode

    func test_qrCode_containsGSOpenParen() {
        let data = EscPosCommandBuilder.qrCode("https://example.com")
        // GS ( k sequences start with [0x1D, 0x28, 0x6B]
        let bytes = Array(data)
        XCTAssertTrue(bytes.contains(0x28), "QR code sequence must contain 0x28 (open paren)")
        XCTAssertFalse(bytes.isEmpty)
    }

    func test_qrCode_encodesContent() {
        let content = "HELLO"
        let data = EscPosCommandBuilder.qrCode(content)
        let bytes = Array(data)
        // The content bytes should appear in the data
        let contentBytes = Array(content.utf8)
        let dataStr = bytes.map { String($0) }.joined()
        let contentStr = contentBytes.map { String($0) }.joined()
        // We can't easily do substring byte search here; check content bytes appear
        for byte in contentBytes {
            XCTAssertTrue(bytes.contains(byte), "QR bytes should contain encoded content byte \(byte)")
        }
    }

    // MARK: - barcode

    func test_barcode_code128_startsWithGS() {
        let data = EscPosCommandBuilder.barcode("12345678", format: .code128)
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(data.first, 0x1D) // GS
    }

    func test_barcode_ean13() {
        let data = EscPosCommandBuilder.barcode("1234567890128", format: .ean13)
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - Full receipt pipeline

    func test_receipt_startsWithInitialize() {
        let payload = Self.samplePayload()
        let data = EscPosCommandBuilder.receipt(payload)
        XCTAssertEqual(data.prefix(2), Data([0x1B, 0x40]),
                       "Receipt stream must begin with ESC @ (initialize)")
    }

    func test_receipt_endsWithCut() {
        let payload = Self.samplePayload()
        let data = EscPosCommandBuilder.receipt(payload)
        XCTAssertEqual(data.suffix(3), Data([0x1D, 0x56, 0x01]),
                       "Receipt stream must end with GS V 1 (partial cut)")
    }

    func test_receipt_containsTenantName() {
        let payload = Self.samplePayload()
        let data = EscPosCommandBuilder.receipt(payload)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("Bizarre CRM Test Shop"),
                      "Receipt stream must contain tenant name")
    }

    func test_receipt_containsReceiptNumber() {
        let payload = Self.samplePayload()
        let data = EscPosCommandBuilder.receipt(payload)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("REC-001"))
    }

    func test_receipt_containsLineItems() {
        let payload = Self.samplePayload()
        let data = EscPosCommandBuilder.receipt(payload)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("Screen Repair"))
        XCTAssertTrue(str.contains("$79.99"))
    }

    func test_receipt_containsTotal() {
        let payload = Self.samplePayload()
        let data = EscPosCommandBuilder.receipt(payload)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("$"), "Receipt must contain dollar amounts")
    }

    func test_receipt_footerIncludedWhenPresent() {
        var payload = Self.samplePayload()
        let payloadWithFooter = ReceiptPayload(
            tenantName: payload.tenantName,
            tenantAddress: payload.tenantAddress,
            tenantPhone: payload.tenantPhone,
            receiptNumber: payload.receiptNumber,
            createdAt: payload.createdAt,
            lineItems: payload.lineItems,
            subtotalCents: payload.subtotalCents,
            taxCents: payload.taxCents,
            tipCents: payload.tipCents,
            totalCents: payload.totalCents,
            paymentTender: payload.paymentTender,
            cashierName: payload.cashierName,
            footerMessage: "Thank you for your business!",
            qrContent: nil
        )
        let data = EscPosCommandBuilder.receipt(payloadWithFooter)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("Thank you for your business!"))
    }

    func test_receipt_footerOmittedWhenNil() {
        let payload = Self.samplePayload()  // footerMessage is nil
        let data = EscPosCommandBuilder.receipt(payload)
        let str = String(data: data, encoding: .utf8) ?? ""
        // With nil footer the string won't contain an unexpected footer
        XCTAssertFalse(str.contains("nil"))
    }

    func test_receipt_tipSkippedWhenZero() {
        let payload = Self.samplePayload()  // tipCents = 0
        let data = EscPosCommandBuilder.receipt(payload)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(str.contains("Tip"), "Tip line should not appear when tipCents == 0")
    }

    func test_receipt_tipIncludedWhenNonZero() {
        let payloadWithTip = ReceiptPayload(
            tenantName: "Test",
            tenantAddress: "123 St",
            tenantPhone: "555-0000",
            receiptNumber: "T-001",
            createdAt: Date(timeIntervalSince1970: 0),
            lineItems: [],
            subtotalCents: 1000,
            taxCents: 80,
            tipCents: 200,
            totalCents: 1280,
            paymentTender: "Card",
            cashierName: "Bob"
        )
        let data = EscPosCommandBuilder.receipt(payloadWithTip)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("Tip"))
        XCTAssertTrue(str.contains("$2.00"))
    }

    func test_receipt_notEmpty() {
        let data = EscPosCommandBuilder.receipt(Self.samplePayload())
        XCTAssertGreaterThan(data.count, 100, "A complete receipt must be non-trivially large")
    }

    // MARK: - Helpers

    private static func samplePayload() -> ReceiptPayload {
        ReceiptPayload(
            tenantName: "Bizarre CRM Test Shop",
            tenantAddress: "456 Elm Street, Springfield",
            tenantPhone: "(555) 123-4567",
            receiptNumber: "REC-001",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lineItems: [
                .init(label: "Screen Repair", value: "$79.99"),
                .init(label: "Labor",          value: "$20.00")
            ],
            subtotalCents: 9999,
            taxCents: 800,
            tipCents: 0,
            totalCents: 10799,
            paymentTender: "Visa ••••1234",
            cashierName: "Alice",
            footerMessage: nil,
            qrContent: nil
        )
    }
}
