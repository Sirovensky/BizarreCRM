import Foundation
import Networking

// §7.7 PaymentHistoryEntry model + builder — no UIKit dependency, testable on macOS.

public enum PaymentHistoryKind: Sendable, Equatable {
    case payment
    case refund
    case void
}

public struct PaymentHistoryEntry: Sendable, Identifiable {
    public let id: Int64
    public let kind: PaymentHistoryKind
    public let tender: String?
    public let amountCents: Int
    public let timestamp: String
    public let operatorName: String?
    public let notes: String?

    public init(
        id: Int64,
        kind: PaymentHistoryKind,
        tender: String?,
        amountCents: Int,
        timestamp: String,
        operatorName: String?,
        notes: String?
    ) {
        self.id = id
        self.kind = kind
        self.tender = tender
        self.amountCents = amountCents
        self.timestamp = timestamp
        self.operatorName = operatorName
        self.notes = notes
    }
}

/// Build payment history entries from an InvoiceDetail.
public func buildPaymentHistory(from invoice: InvoiceDetail) -> [PaymentHistoryEntry] {
    var entries: [PaymentHistoryEntry] = []

    if let payments = invoice.payments {
        for p in payments {
            let kind: PaymentHistoryKind
            switch (p.paymentType ?? "").lowercased() {
            case "refund": kind = .refund
            default:       kind = .payment
            }
            let cents: Int
            if let amount = p.amount {
                cents = Int((amount * 100).rounded())
            } else {
                cents = 0
            }
            entries.append(PaymentHistoryEntry(
                id: p.id,
                kind: kind,
                tender: p.method,
                amountCents: kind == .refund ? -cents : cents,
                timestamp: p.createdAt ?? "",
                operatorName: p.recordedBy,
                notes: p.notes
            ))
        }
    }

    if invoice.status?.lowercased() == "void" {
        entries.append(PaymentHistoryEntry(
            id: -1,
            kind: .void,
            tender: nil,
            amountCents: 0,
            timestamp: invoice.updatedAt ?? "",
            operatorName: nil,
            notes: nil
        ))
    }

    return entries.sorted { $0.timestamp > $1.timestamp }
}
