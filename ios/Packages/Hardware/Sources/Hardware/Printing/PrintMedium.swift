#if canImport(SwiftUI)
import SwiftUI

// MARK: - PrintMedium
//
// Describes the physical output medium. Views read `@Environment(\.printMedium)`
// to adapt fonts, column widths, and margins so a single SwiftUI view renders
// correctly on a 80mm thermal roll, a 58mm roll, Letter paper, or a label.
//
// Usage:
// ```swift
// struct ReceiptView: View {
//     @Environment(\.printMedium) private var medium
//     var body: some View {
//         Text("Total")
//             .font(medium.bodyFont)
//             .frame(width: medium.contentWidth)
//     }
// }
// // Preview:
// ReceiptView(model: payload).environment(\.printMedium, .thermal80mm)
// ```

public enum PrintMedium: String, CaseIterable, Sendable {
    /// Star TSP100IV, Epson TM-T88 — 80mm roll, ~72mm printable.
    case thermal80mm
    /// Seiko / Citizen compact printers — 58mm roll, ~48mm printable.
    case thermal58mm
    /// US Letter page (8.5 × 11 in).
    case letter
    /// A4 page (210 × 297 mm).
    case a4
    /// 4" × 6" shipping / receipt label.
    case label4x6
    /// 2" × 4" small label.
    case label2x4
    /// US Legal page (8.5 × 14 in).
    case legal

    // MARK: - Physical dimensions (points at 72 dpi)

    /// Printable content width in points.
    public var contentWidth: CGFloat {
        switch self {
        case .thermal80mm: return 204  // ~72 mm at 72 dpi
        case .thermal58mm: return 136  // ~48 mm at 72 dpi
        case .letter:      return 468  // 6.5 in at 72 dpi
        case .a4:          return 481  // 168 mm at 72 dpi
        case .label4x6:    return 288  // 4 in at 72 dpi
        case .label2x4:    return 144  // 2 in at 72 dpi
        case .legal:       return 468  // 6.5 in at 72 dpi (same margin as letter)
        }
    }

    /// Total page width in points (including margins).
    public var pageWidth: CGFloat {
        switch self {
        case .thermal80mm: return 226  // 80mm at 72 dpi
        case .thermal58mm: return 165  // 58mm at 72 dpi
        case .letter:      return 612  // 8.5 in
        case .a4:          return 595  // 210 mm
        case .label4x6:    return 288
        case .label2x4:    return 144
        case .legal:       return 612  // 8.5 in
        }
    }

    /// Total page height in points.
    public var pageHeight: CGFloat {
        switch self {
        case .thermal80mm, .thermal58mm: return 0   // continuous feed — no fixed height
        case .letter:      return 792  // 11 in
        case .a4:          return 842  // 297 mm
        case .label4x6:    return 432  // 6 in
        case .label2x4:    return 288  // 4 in
        case .legal:       return 1008 // 14 in
        }
    }

    /// Lateral margin on each side (points).
    public var sideMargin: CGFloat { (pageWidth - contentWidth) / 2 }

    /// Top/bottom margin (points). Used by the paginated PDF renderer to leave
    /// breathing room between content slices and page edges.
    public var margin: CGFloat {
        switch self {
        case .thermal80mm, .thermal58mm: return 4
        case .letter, .a4, .legal:       return 36  // 0.5 in
        case .label4x6, .label2x4:      return 8
        }
    }

    // MARK: - Fonts

    /// Header font (tenant name / document title).
    public var headerFont: Font {
        switch self {
        case .thermal80mm, .thermal58mm: return .system(size: 12, weight: .bold, design: .monospaced)
        case .letter, .a4, .legal:       return .system(size: 16, weight: .bold)
        case .label4x6, .label2x4:      return .system(size: 10, weight: .bold)
        }
    }

    /// Body font (line items, cashier, date).
    public var bodyFont: Font {
        switch self {
        case .thermal80mm, .thermal58mm: return .system(size: 9, design: .monospaced)
        case .letter, .a4, .legal:       return .system(size: 11)
        case .label4x6, .label2x4:      return .system(size: 8)
        }
    }

    /// Small/caption font (footer, hints).
    public var captionFont: Font {
        switch self {
        case .thermal80mm, .thermal58mm: return .system(size: 7, design: .monospaced)
        case .letter, .a4, .legal:       return .system(size: 9)
        case .label4x6, .label2x4:      return .system(size: 7)
        }
    }

    /// Whether the medium fits two columns for line items.
    public var twoColumnLineItems: Bool {
        switch self {
        case .letter, .a4, .legal: return true
        default: return false
        }
    }

    /// Display name for UI (Settings, test-print sheet).
    public var displayName: String {
        switch self {
        case .thermal80mm: return "80 mm Thermal"
        case .thermal58mm: return "58 mm Thermal"
        case .letter:      return "Letter (8.5 × 11)"
        case .a4:          return "A4"
        case .label4x6:    return "4\" × 6\" Label"
        case .label2x4:    return "2\" × 4\" Label"
        case .legal:       return "Legal (8.5 × 14)"
        }
    }

    /// Default paper size for US tenants (Settings → Printing).
    public static var tenantDefault: PrintMedium {
        let regionCode = Locale.current.region?.identifier ?? "US"
        // US and Canada default to letter; rest of world to A4.
        return (regionCode == "US" || regionCode == "CA") ? .letter : .a4
    }
}

// MARK: - EnvironmentKey

private struct PrintMediumKey: EnvironmentKey {
    static let defaultValue: PrintMedium = .thermal80mm
}

public extension EnvironmentValues {
    var printMedium: PrintMedium {
        get { self[PrintMediumKey.self] }
        set { self[PrintMediumKey.self] = newValue }
    }
}
#endif
