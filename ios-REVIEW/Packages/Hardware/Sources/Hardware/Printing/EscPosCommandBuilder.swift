import Foundation

// MARK: - ESC/POS Command Builder
//
// Pure byte-building helper. No I/O, no UIKit, no Foundation beyond Data.
// Testable in isolation on any platform.
//
// Reference: EPSON ESC/POS Application Programming Guide
// https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/

public enum EscPosCommandBuilder {

    // MARK: - ESC/POS Constants

    private static let ESC: UInt8  = 0x1B
    private static let GS: UInt8   = 0x1D
    private static let LF: UInt8   = 0x0A
    private static let NUL: UInt8  = 0x00

    // MARK: - Top-level receipt builder

    /// Builds a complete ESC/POS byte stream for a `ReceiptPayload`.
    /// Pipeline:  init → header → lines → totals → tender → footer → feed → cut
    public static func receipt(_ payload: ReceiptPayload) -> Data {
        var data = Data()
        data.append(contentsOf: initialize())
        data.append(contentsOf: align(.center))
        data.append(contentsOf: fontSize(width: 2, height: 2))
        data.append(contentsOf: text(payload.tenantName))
        data.append(contentsOf: feed(1))
        data.append(contentsOf: fontSize(width: 1, height: 1))
        data.append(contentsOf: text(payload.tenantAddress))
        data.append(contentsOf: feed(1))
        data.append(contentsOf: text(payload.tenantPhone))
        data.append(contentsOf: feed(1))
        data.append(contentsOf: separator())
        data.append(contentsOf: align(.left))
        data.append(contentsOf: text("Receipt: \(payload.receiptNumber)"))
        data.append(contentsOf: feed(1))
        data.append(contentsOf: text("Date: \(Self.formatDate(payload.createdAt))"))
        data.append(contentsOf: feed(1))
        data.append(contentsOf: text("Cashier: \(payload.cashierName)"))
        data.append(contentsOf: feed(1))
        data.append(contentsOf: separator())
        for item in payload.lineItems {
            data.append(contentsOf: lineItem(label: item.label, value: item.value))
        }
        data.append(contentsOf: separator())
        data.append(contentsOf: lineItem(label: "Subtotal", value: Self.formatCents(payload.subtotalCents)))
        data.append(contentsOf: lineItem(label: "Tax",      value: Self.formatCents(payload.taxCents)))
        if payload.tipCents > 0 {
            data.append(contentsOf: lineItem(label: "Tip", value: Self.formatCents(payload.tipCents)))
        }
        data.append(contentsOf: bold(true))
        data.append(contentsOf: lineItem(label: "TOTAL", value: Self.formatCents(payload.totalCents)))
        data.append(contentsOf: bold(false))
        data.append(contentsOf: lineItem(label: "Tender", value: payload.paymentTender))
        data.append(contentsOf: separator())
        if let footer = payload.footerMessage, !footer.isEmpty {
            data.append(contentsOf: align(.center))
            data.append(contentsOf: text(footer))
            data.append(contentsOf: feed(1))
        }
        if let qr = payload.qrContent, !qr.isEmpty {
            data.append(contentsOf: qrCode(qr))
        }
        data.append(contentsOf: feed(4))
        data.append(contentsOf: cut(partial: true))
        return data
    }

    // MARK: - Individual commands

    /// ESC @ — Initialize printer (reset to defaults).
    public static func initialize() -> Data {
        Data([ESC, 0x40])
    }

    /// ESC a n — Select justification.
    public static func align(_ alignment: Alignment) -> Data {
        Data([ESC, 0x61, alignment.rawValue])
    }

    /// ESC ! n — Select print mode (font + bold + double-size composite).
    public static func printMode(_ mode: UInt8) -> Data {
        Data([ESC, 0x21, mode])
    }

    /// ESC E n — Turn emphasis (bold) on/off.
    public static func bold(_ on: Bool) -> Data {
        Data([ESC, 0x45, on ? 1 : 0])
    }

    /// GS ! n — Select character size (width multiplier 1–8, height multiplier 1–8).
    public static func fontSize(width: Int, height: Int) -> Data {
        let w = UInt8(max(1, min(8, width)) - 1)
        let h = UInt8(max(1, min(8, height)) - 1)
        let n: UInt8 = (w << 4) | h
        return Data([GS, 0x21, n])
    }

    /// ESC d n — Print and feed n lines.
    public static func feed(_ lines: Int) -> Data {
        Data([ESC, 0x64, UInt8(max(0, min(255, lines)))])
    }

    /// GS V m — Paper cut.
    ///   partial = true → GS V 1 (partial cut)
    ///   partial = false → GS V 0 (full cut)
    public static func cut(partial: Bool) -> Data {
        Data([GS, 0x56, partial ? 1 : 0])
    }

    /// GS k m d1..dk NUL — Print barcode.
    ///
    /// Supports CODE128 (m=73) only for now.
    public static func barcode(_ code: String, format: BarcodeFormat) -> Data {
        var data = Data()
        // Set barcode height (GS h n)
        data.append(contentsOf: [GS, 0x68, 80])
        // Set HRI position below barcode (GS H 2)
        data.append(contentsOf: [GS, 0x48, 2])
        switch format {
        case .code128:
            // GS k 73 (CODE128), followed by length byte, then data
            let encoded = Array(code.utf8)
            data.append(contentsOf: [GS, 0x6B, 73, UInt8(encoded.count)])
            data.append(contentsOf: encoded)
        case .upca:
            let encoded = Array(code.utf8)
            data.append(contentsOf: [GS, 0x6B, 65, UInt8(encoded.count)])
            data.append(contentsOf: encoded)
        case .ean13:
            let encoded = Array(code.utf8)
            data.append(contentsOf: [GS, 0x6B, 67, UInt8(encoded.count)])
            data.append(contentsOf: encoded)
        case .qr:
            data.append(contentsOf: qrCode(code))
        }
        return data
    }

    /// QR code via GS ( k — model 2 QR code sequence.
    public static func qrCode(_ content: String) -> Data {
        var data = Data()
        let payload = Array(content.utf8)
        let pLen = payload.count + 3
        let pH = UInt8(pLen / 256)
        let pL = UInt8(pLen % 256)

        // GS ( k — Select QR model 2
        data.append(contentsOf: [GS, 0x28, 0x6B, 4, 0, 49, 65, 50, 0])
        // GS ( k — Set error correction level M
        data.append(contentsOf: [GS, 0x28, 0x6B, 3, 0, 49, 69, 77])
        // GS ( k — Store data
        data.append(contentsOf: [GS, 0x28, 0x6B, pL, pH, 49, 80, 48])
        data.append(contentsOf: payload)
        // GS ( k — Print
        data.append(contentsOf: [GS, 0x28, 0x6B, 3, 0, 49, 81, 48])
        return data
    }

    /// Cash drawer kick via ESC/POS pin 2 (standard).
    public static func drawerKick() -> Data {
        // ESC p 0 25 250 — kick pin 2, on=25ms off=250ms
        Data([ESC, 0x70, 0, 25, 250])
    }

    // MARK: - Convenience helpers (not commands)

    /// Raw text bytes + LF.
    public static func text(_ string: String) -> Data {
        var data = Data(string.utf8)
        data.append(LF)
        return data
    }

    /// Full-width dashes separator line.
    public static func separator(width: Int = 42) -> Data {
        text(String(repeating: "-", count: width))
    }

    /// Two-column line item (left-aligned label, right-aligned value).
    public static func lineItem(label: String, value: String, totalWidth: Int = 42) -> Data {
        let gap = max(1, totalWidth - label.count - value.count)
        return text(label + String(repeating: " ", count: gap) + value)
    }

    // MARK: - Private helpers

    private static func formatCents(_ cents: Int) -> String {
        let dollars = abs(cents) / 100
        let pennies = abs(cents) % 100
        let sign = cents < 0 ? "-" : ""
        return "\(sign)$\(dollars).\(String(format: "%02d", pennies))"
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Alignment Enum

public extension EscPosCommandBuilder {
    enum Alignment: UInt8 {
        case left   = 0
        case center = 1
        case right  = 2
    }
}
