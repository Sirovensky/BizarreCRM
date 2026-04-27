#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.2 Invoice Timeline — every status change, payment, note, email/SMS send.
// Events are built client-side from the data available in InvoiceDetail (payments,
// status, notes, createdAt, updatedAt). Server-side event log is future work.

// MARK: - Model

public enum InvoiceTimelineEvent: Sendable, Identifiable {
    case created(at: String, by: String?)
    case statusChanged(to: String, at: String)
    case paymentRecorded(method: String?, amountCents: Int, at: String, by: String?)
    case refundIssued(amountCents: Int, at: String, by: String?)
    case voided(at: String)
    case noted(text: String, at: String)

    public var id: String {
        switch self {
        case .created(let at, _):             return "created-\(at)"
        case .statusChanged(let to, let at):  return "status-\(to)-\(at)"
        case .paymentRecorded(_, let c, let at, _): return "pay-\(c)-\(at)"
        case .refundIssued(let c, let at, _): return "refund-\(c)-\(at)"
        case .voided(let at):                 return "void-\(at)"
        case .noted(_, let at):               return "note-\(at)"
        }
    }

    public var timestamp: String {
        switch self {
        case .created(let at, _):             return at
        case .statusChanged(_, let at):       return at
        case .paymentRecorded(_, _, let at, _): return at
        case .refundIssued(_, let at, _):     return at
        case .voided(let at):                 return at
        case .noted(_, let at):               return at
        }
    }

    var iconName: String {
        switch self {
        case .created:         return "doc.badge.plus"
        case .statusChanged:   return "arrow.triangle.2.circlepath"
        case .paymentRecorded: return "creditcard.fill"
        case .refundIssued:    return "arrow.uturn.left"
        case .voided:          return "xmark.circle.fill"
        case .noted:           return "note.text"
        }
    }

    var iconColor: Color {
        switch self {
        case .created:         return .bizarreOrange
        case .statusChanged:   return .bizarrePrimary
        case .paymentRecorded: return .bizarreSuccess
        case .refundIssued:    return .bizarreWarning
        case .voided:          return .bizarreError
        case .noted:           return .bizarreOnSurfaceMuted
        }
    }

    var title: String {
        switch self {
        case .created(_, let by):
            let actor = by.flatMap { $0.isEmpty ? nil : $0 } ?? "System"
            return "Invoice created by \(actor)"
        case .statusChanged(let to, _):
            return "Status changed to \(to.capitalized)"
        case .paymentRecorded(let method, let cents, _, let by):
            let actor = by.flatMap { $0.isEmpty ? nil : $0 }
            let amount = formatMoney(Double(cents) / 100.0)
            let via = method.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown method"
            if let actor {
                return "Payment of \(amount) via \(via) — \(actor)"
            }
            return "Payment of \(amount) via \(via)"
        case .refundIssued(let cents, _, let by):
            let actor = by.flatMap { $0.isEmpty ? nil : $0 }
            let amount = formatMoney(Double(cents) / 100.0)
            if let actor {
                return "Refund of \(amount) by \(actor)"
            }
            return "Refund of \(amount)"
        case .voided:
            return "Invoice voided"
        case .noted(let text, _):
            return text.isEmpty ? "Note added" : text
        }
    }
}

// MARK: - Builder

public func buildInvoiceTimeline(from invoice: InvoiceDetail) -> [InvoiceTimelineEvent] {
    var events: [InvoiceTimelineEvent] = []

    // Created event
    if let created = invoice.createdAt {
        events.append(.created(at: created, by: invoice.createdByName))
    }

    // Payment + refund events
    if let payments = invoice.payments {
        for p in payments {
            let at = p.createdAt ?? ""
            let type = (p.paymentType ?? "payment").lowercased()
            let cents = Int(((p.amount ?? 0) * 100).rounded())
            if type == "refund" {
                events.append(.refundIssued(amountCents: cents, at: at, by: p.recordedBy))
            } else {
                events.append(.paymentRecorded(method: p.method, amountCents: cents, at: at, by: p.recordedBy))
            }
        }
    }

    // Void event
    if (invoice.status ?? "").lowercased() == "void", let updated = invoice.updatedAt {
        events.append(.voided(at: updated))
    }

    // Notes event (if present)
    if let notes = invoice.notes, !notes.isEmpty, let created = invoice.createdAt {
        events.append(.noted(text: notes, at: created))
    }

    return events.sorted { $0.timestamp > $1.timestamp }
}

// MARK: - View

public struct InvoiceTimelineView: View {
    let events: [InvoiceTimelineEvent]

    public init(events: [InvoiceTimelineEvent]) {
        self.events = events
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Timeline")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.bottom, BrandSpacing.sm)

            if events.isEmpty {
                Text("No events recorded yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.vertical, BrandSpacing.sm)
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    timelineRow(event: event, isLast: index == events.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    @ViewBuilder
    private func timelineRow(event: InvoiceTimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // Icon + vertical line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(event.iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: event.iconName)
                        .foregroundStyle(event.iconColor)
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.bizarreOutline.opacity(0.4))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(event.title)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel(event.title)
                Text(formatTimestamp(event.timestamp))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            .padding(.bottom, isLast ? 0 : BrandSpacing.base)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Helpers

private func formatTimestamp(_ iso: String) -> String {
    guard !iso.isEmpty else { return "—" }
    let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    for fmt in formats {
        f.dateFormat = fmt
        if let date = f.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
    }
    return String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
}

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
#endif
