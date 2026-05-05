import Foundation

// DeadLetterItem Hashable conformance for SwiftUI List(selection:) + .tag(_:).
// Uses id + movedAt for equality since DeadLetterItem already has Identifiable.
// Extension-only so the canonical struct in DeadLetterRepository.swift stays
// untouched.

extension DeadLetterItem: Hashable {
    public static func == (lhs: DeadLetterItem, rhs: DeadLetterItem) -> Bool {
        lhs.id == rhs.id && lhs.movedAt == rhs.movedAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(movedAt)
    }
}
