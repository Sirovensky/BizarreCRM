import Foundation

/// §18.7 — Value type capturing all active search filter values.
public struct SearchFilters: Hashable, Sendable {
    public var entity: EntityFilter
    public var dateFrom: Date?
    public var dateTo: Date?
    public var status: String?
    public var assignee: String?
    public var creator: String?

    public init(
        entity: EntityFilter = .all,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        status: String? = nil,
        assignee: String? = nil,
        creator: String? = nil
    ) {
        self.entity = entity
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.status = status
        self.assignee = assignee
        self.creator = creator
    }

    public var isDefault: Bool {
        entity == .all
        && dateFrom == nil
        && dateTo == nil
        && status == nil
        && assignee == nil
        && creator == nil
    }
}
