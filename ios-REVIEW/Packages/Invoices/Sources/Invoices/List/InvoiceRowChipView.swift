#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// §7.1 Invoice row chips
// "Overdue 3d" (red) / "Paid 50%" (amber) / "Unpaid" (gray) / "Paid" (green) / "Void" (strike-through)

public struct InvoiceRowChip: View {
    let invoice: InvoiceSummary

    public var body: some View {
        let descriptor = InvoiceRowChipDescriptor(invoice: invoice)
        return Text(descriptor.label)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(descriptor.foreground)
            .background(descriptor.background, in: Capsule())
            .strikethrough(descriptor.strikethrough, color: descriptor.foreground)
            .accessibilityLabel(descriptor.a11yLabel)
    }
}

// MARK: - Descriptor (pure, testable)

public struct InvoiceRowChipDescriptor: Sendable {
    public let label: String
    public let background: Color
    public let foreground: Color
    public let strikethrough: Bool
    public let a11yLabel: String

    public init(invoice: InvoiceSummary) {
        let status = invoice.status?.lowercased() ?? ""
        let totalCents = Int(((invoice.total ?? 0) * 100).rounded())
        let paidCents  = Int(((invoice.amountPaid ?? 0) * 100).rounded())
        let dueCents   = Int(((invoice.amountDue ?? 0) * 100).rounded())

        // Compute overdue days from dueOn
        let overdueDays: Int? = {
            guard let dueStr = invoice.dueOn, !dueStr.isEmpty else { return nil }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            guard let dueDate = df.date(from: String(dueStr.prefix(10))) else { return nil }
            let days = Calendar.current.dateComponents([.day], from: dueDate, to: Date()).day ?? 0
            return days > 0 ? days : nil
        }()

        switch status {
        case "void":
            self.label = "Void"
            self.background = Color.bizarreOnSurfaceMuted.opacity(0.2)
            self.foreground = .bizarreOnSurfaceMuted
            self.strikethrough = true
            self.a11yLabel = "Invoice voided"

        case "paid":
            self.label = "Paid"
            self.background = .bizarreSuccess
            self.foreground = .black
            self.strikethrough = false
            self.a11yLabel = "Fully paid"

        case "partial":
            // Show "Paid X%"
            let pct = totalCents > 0 ? Int((Double(paidCents) / Double(totalCents) * 100).rounded()) : 0
            self.label = "Paid \(pct)%"
            self.background = .bizarreWarning
            self.foreground = .black
            self.strikethrough = false
            self.a11yLabel = "\(pct) percent paid"

        case "overdue":
            if let days = overdueDays {
                self.label = "Overdue \(days)d"
            } else {
                self.label = "Overdue"
            }
            self.background = .bizarreError
            self.foreground = .white
            self.strikethrough = false
            self.a11yLabel = overdueDays.map { "Overdue by \($0) days" } ?? "Overdue"

        default:
            // "unpaid" or unknown
            self.label = dueCents > 0 ? "Unpaid" : "—"
            self.background = Color.bizarreSurface2
            self.foreground = .bizarreOnSurfaceMuted
            self.strikethrough = false
            self.a11yLabel = "Unpaid"
        }
    }
}
#endif
