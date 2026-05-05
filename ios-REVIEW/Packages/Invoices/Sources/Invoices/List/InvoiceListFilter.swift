import Foundation
import Networking

// §7.1 InvoiceListFilter — 5-axis advanced filter
// Axes: date range, customer, amount range, payment method, created-by

public struct InvoiceListFilter: Equatable, Sendable {
    // Date range
    public var dateRangeStart: Date?
    public var dateRangeEnd: Date?

    // Customer name / id search
    public var customerName: String = ""

    // Amount range (dollars)
    public var amountMin: Double?
    public var amountMax: Double?

    // Payment method
    public var paymentMethod: String?

    // Created-by (employee name filter, server param: created_by)
    public var createdBy: String = ""

    public init() {}

    public var isActive: Bool {
        dateRangeStart != nil
            || dateRangeEnd != nil
            || !customerName.isEmpty
            || amountMin != nil
            || amountMax != nil
            || paymentMethod != nil
            || !createdBy.isEmpty
    }

    // MARK: - Query items for GET /invoices

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let start = dateRangeStart {
            items.append(URLQueryItem(name: "date_from", value: iso.string(from: start)))
        }
        if let end = dateRangeEnd {
            items.append(URLQueryItem(name: "date_to", value: iso.string(from: end)))
        }
        if !customerName.isEmpty {
            items.append(URLQueryItem(name: "customer", value: customerName))
        }
        if let min = amountMin {
            items.append(URLQueryItem(name: "amount_min", value: String(format: "%.2f", min)))
        }
        if let max = amountMax {
            items.append(URLQueryItem(name: "amount_max", value: String(format: "%.2f", max)))
        }
        if let method = paymentMethod, !method.isEmpty {
            items.append(URLQueryItem(name: "payment_method", value: method))
        }
        if !createdBy.isEmpty {
            items.append(URLQueryItem(name: "created_by", value: createdBy))
        }
        return items
    }
}

// MARK: - Known payment methods (matches server enum)

public enum InvoicePaymentMethodFilter: String, CaseIterable, Sendable, Identifiable {
    case cash        = "cash"
    case card        = "card"
    case ach         = "ach"
    case check       = "check"
    case giftCard    = "gift_card"
    case storeCredit = "store_credit"
    case other       = "other"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cash:        return "Cash"
        case .card:        return "Card"
        case .ach:         return "ACH"
        case .check:       return "Check"
        case .giftCard:    return "Gift Card"
        case .storeCredit: return "Store Credit"
        case .other:       return "Other"
        }
    }
}
