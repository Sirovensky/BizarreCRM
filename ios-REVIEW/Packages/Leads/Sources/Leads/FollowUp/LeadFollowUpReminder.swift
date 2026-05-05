import Foundation

// MARK: - LeadFollowUpReminder

/// Local model for a follow-up reminder. Mirrors `LeadFollowUpResponse` from the network layer
/// but adds client-side convenience properties.
public struct LeadFollowUpReminder: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let leadId: Int64
    public let dueAt: Date
    public let note: String
    public let completed: Bool

    public init(id: Int64, leadId: Int64, dueAt: Date, note: String, completed: Bool = false) {
        self.id = id
        self.leadId = leadId
        self.dueAt = dueAt
        self.note = note
        self.completed = completed
    }

    public var isDueToday: Bool {
        Calendar.current.isDateInToday(dueAt)
    }

    public var isOverdue: Bool {
        !completed && dueAt < Date() && !isDueToday
    }

    public var dueDateLabel: String {
        if isDueToday { return "Today" }
        if isOverdue { return "Overdue" }
        return dueAt.formatted(date: .abbreviated, time: .shortened)
    }
}
