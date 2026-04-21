import Foundation

/// Money amounts in cents.
public typealias Cents = Int

// MARK: - Invoice

/// Canonical domain model for an invoice.
/// Wire DTOs live in Networking/Endpoints/InvoiceDetailEndpoints.swift
/// (InvoiceDetail) and Networking/Endpoints/InvoicesEndpoints.swift (InvoiceSummary).
/// This struct is the stable cross-package currency; feature packages map from
/// the wire DTO into Invoice for persistence and business logic.
public struct Invoice: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let orderId: String?
    public let customerId: Int64?
    public let ticketId: Int64?
    public let status: InvoiceStatus
    public let subtotalCents: Cents
    public let discountCents: Cents
    public let taxCents: Cents
    public let totalCents: Cents
    public let amountPaidCents: Cents
    public let amountDueCents: Cents
    public let notes: String?
    public let dueOn: Date?
    public let lineItems: [InvoiceLineItem]
    public let payments: [InvoicePayment]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int64,
        orderId: String? = nil,
        customerId: Int64? = nil,
        ticketId: Int64? = nil,
        status: InvoiceStatus = .unpaid,
        subtotalCents: Cents = 0,
        discountCents: Cents = 0,
        taxCents: Cents = 0,
        totalCents: Cents = 0,
        amountPaidCents: Cents = 0,
        amountDueCents: Cents = 0,
        notes: String? = nil,
        dueOn: Date? = nil,
        lineItems: [InvoiceLineItem] = [],
        payments: [InvoicePayment] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.orderId = orderId
        self.customerId = customerId
        self.ticketId = ticketId
        self.status = status
        self.subtotalCents = subtotalCents
        self.discountCents = discountCents
        self.taxCents = taxCents
        self.totalCents = totalCents
        self.amountPaidCents = amountPaidCents
        self.amountDueCents = amountDueCents
        self.notes = notes
        self.dueOn = dueOn
        self.lineItems = lineItems
        self.payments = payments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayId: String { orderId?.isEmpty == false ? orderId! : "INV-\(id)" }
    public var isOverdue: Bool {
        guard let due = dueOn, status != .paid, status != .void else { return false }
        return due < Date()
    }
}

// MARK: - InvoiceStatus

public enum InvoiceStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case unpaid
    case partial
    case paid
    case void

    public var displayName: String {
        switch self {
        case .unpaid:  return "Unpaid"
        case .partial: return "Partial"
        case .paid:    return "Paid"
        case .void:    return "Void"
        }
    }
}

// MARK: - InvoiceLineItem

public struct InvoiceLineItem: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let invoiceId: Int64?
    public let inventoryItemId: Int64?
    public let itemName: String?
    public let description: String?
    public let sku: String?
    /// Server returns fractional quantities (e.g. 1.5 hours).
    public let quantity: Double
    public let unitPriceCents: Cents
    public let discountCents: Cents
    public let taxCents: Cents
    public let totalCents: Cents

    public init(
        id: Int64,
        invoiceId: Int64? = nil,
        inventoryItemId: Int64? = nil,
        itemName: String? = nil,
        description: String? = nil,
        sku: String? = nil,
        quantity: Double = 1,
        unitPriceCents: Cents = 0,
        discountCents: Cents = 0,
        taxCents: Cents = 0,
        totalCents: Cents = 0
    ) {
        self.id = id
        self.invoiceId = invoiceId
        self.inventoryItemId = inventoryItemId
        self.itemName = itemName
        self.description = description
        self.sku = sku
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.discountCents = discountCents
        self.taxCents = taxCents
        self.totalCents = totalCents
    }

    public var displayName: String {
        if let n = itemName, !n.isEmpty { return n }
        if let d = description, !d.isEmpty { return d }
        return "Item"
    }
}

// MARK: - InvoicePayment

public struct InvoicePayment: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let amountCents: Cents
    public let method: String?
    public let methodDetail: String?
    public let transactionId: String?
    public let notes: String?
    public let paymentType: String?
    public let recordedBy: String?
    public let createdAt: Date?

    public init(
        id: Int64,
        amountCents: Cents = 0,
        method: String? = nil,
        methodDetail: String? = nil,
        transactionId: String? = nil,
        notes: String? = nil,
        paymentType: String? = nil,
        recordedBy: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.amountCents = amountCents
        self.method = method
        self.methodDetail = methodDetail
        self.transactionId = transactionId
        self.notes = notes
        self.paymentType = paymentType
        self.recordedBy = recordedBy
        self.createdAt = createdAt
    }
}
