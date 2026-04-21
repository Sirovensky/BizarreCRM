import Foundation

// MARK: - Expense

/// Canonical domain model for a business expense record.
/// Wire DTO: Networking/Endpoints/ExpensesEndpoints.swift (Expense).
public struct Expense: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let category: ExpenseCategory
    public let amountCents: Cents
    public let description: String?
    public let date: Date
    public let receiptPath: String?
    public let submittedByUserId: Int64?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int64,
        category: ExpenseCategory = .other,
        amountCents: Cents = 0,
        description: String? = nil,
        date: Date,
        receiptPath: String? = nil,
        submittedByUserId: Int64? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.category = category
        self.amountCents = amountCents
        self.description = description
        self.date = date
        self.receiptPath = receiptPath
        self.submittedByUserId = submittedByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var hasReceipt: Bool { receiptPath?.isEmpty == false }
}

// MARK: - ExpenseCategory

public enum ExpenseCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case parts
    case supplies
    case shipping
    case utilities
    case rent
    case payroll
    case marketing
    case equipment
    case repairs
    case travel
    case meals
    case other

    public var displayName: String {
        switch self {
        case .parts:      return "Parts"
        case .supplies:   return "Supplies"
        case .shipping:   return "Shipping"
        case .utilities:  return "Utilities"
        case .rent:       return "Rent"
        case .payroll:    return "Payroll"
        case .marketing:  return "Marketing"
        case .equipment:  return "Equipment"
        case .repairs:    return "Repairs"
        case .travel:     return "Travel"
        case .meals:      return "Meals"
        case .other:      return "Other"
        }
    }
}
