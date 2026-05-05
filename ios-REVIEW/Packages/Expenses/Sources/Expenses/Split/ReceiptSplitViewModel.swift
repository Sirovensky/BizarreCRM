import Foundation
import Observation
import Networking
import Core

// MARK: - LineAssignment

/// Per-line category assignment for a split receipt.
public struct LineAssignment: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var lineItem: ReceiptLineItem
    public var category: String
    public var included: Bool

    public init(lineItem: ReceiptLineItem, category: String = "Other", included: Bool = true) {
        self.id = lineItem.id
        self.lineItem = lineItem
        self.category = category
        self.included = included
    }
}

// MARK: - SplitExpenseBody

struct SplitExpenseBody: Encodable, Sendable {
    struct LineAssignmentBody: Encodable, Sendable {
        let lineId: String
        let category: String
        let amountCents: Int

        enum CodingKeys: String, CodingKey {
            case lineId = "line_id"
            case category
            case amountCents = "amount_cents"
        }
    }

    let receiptId: String
    let lineAssignments: [LineAssignmentBody]

    enum CodingKeys: String, CodingKey {
        case receiptId = "receipt_id"
        case lineAssignments = "line_assignments"
    }
}

struct SplitExpenseResponse: Decodable, Sendable {
    let createdCount: Int
    let expenseIds: [Int64]

    enum CodingKeys: String, CodingKey {
        case createdCount = "created_count"
        case expenseIds = "expense_ids"
    }
}

// MARK: - ReceiptSplitViewModel

@MainActor
@Observable
public final class ReceiptSplitViewModel {

    // MARK: - State

    public private(set) var assignments: [LineAssignment]
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var savedExpenseIds: [Int64]?

    private let receiptId: String
    private let api: APIClient

    // MARK: - Available categories (mirrors server list)

    public static let availableCategories: [String] = [
        "Rent", "Utilities", "Parts", "Tools", "Marketing", "Insurance",
        "Payroll", "Software", "Office Supplies", "Shipping", "Travel",
        "Maintenance", "Taxes", "Meals", "Fuel", "Supplies", "Other"
    ]

    // MARK: - Init

    public init(ocrResult: ReceiptOCRResult, receiptId: String, api: APIClient) {
        self.receiptId = receiptId
        self.api = api
        let items = ocrResult.lineItems ?? []
        self.assignments = items.map { item in
            // Auto-guess category from description
            let guessed = ReceiptCategoryGuesser.guess(merchantName: item.description)?.rawValue ?? "Other"
            return LineAssignment(lineItem: item, category: guessed, included: true)
        }
    }

    // MARK: - Mutation (immutable style — replace element in array)

    public func setCategory(_ category: String, for id: UUID) {
        assignments = assignments.map { assignment in
            guard assignment.id == id else { return assignment }
            return LineAssignment(lineItem: assignment.lineItem, category: category, included: assignment.included)
        }
    }

    public func setIncluded(_ included: Bool, for id: UUID) {
        assignments = assignments.map { assignment in
            guard assignment.id == id else { return assignment }
            return LineAssignment(lineItem: assignment.lineItem, category: assignment.category, included: included)
        }
    }

    // MARK: - Computed

    public var totalIncludedCents: Int {
        assignments.filter(\.included).compactMap(\.lineItem.amountCents).reduce(0, +)
    }

    public var includedCount: Int { assignments.filter(\.included).count }

    public var canSave: Bool { includedCount > 0 && !isSaving }

    // MARK: - Save

    public func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let lineAssignments = assignments
            .filter(\.included)
            .map { a in
                SplitExpenseBody.LineAssignmentBody(
                    lineId: a.id.uuidString,
                    category: a.category,
                    amountCents: a.lineItem.amountCents ?? 0
                )
            }

        let body = SplitExpenseBody(receiptId: receiptId, lineAssignments: lineAssignments)

        do {
            let response: SplitExpenseResponse = try await api.post(
                "/api/v1/expenses/split",
                body: body,
                as: SplitExpenseResponse.self
            )
            savedExpenseIds = response.expenseIds
        } catch {
            AppLog.ui.error("Receipt split save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
