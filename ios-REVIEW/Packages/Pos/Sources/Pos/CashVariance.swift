import Foundation
#if canImport(SwiftUI)
import SwiftUI
import DesignSystem
#endif

/// §39 — classification helper for the cash drawer close-out variance.
/// green = 0, amber = ±$5, red = > $5 (notes required).
public enum CashVariance {
    public enum Band: Equatable, Sendable { case green, amber, red }
    public static let amberCeilingCents: Int = 500

    public static func band(cents: Int) -> Band {
        if cents == 0 { return .green }
        return abs(cents) <= amberCeilingCents ? .amber : .red
    }
    public static func notesRequired(cents: Int) -> Bool { band(cents: cents) == .red }
    public static func canCommit(varianceCents: Int, notes: String) -> Bool {
        guard notesRequired(cents: varianceCents) else { return true }
        return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#if canImport(SwiftUI)
public extension CashVariance.Band {
    var color: Color {
        switch self {
        case .green: return .bizarreSuccess
        case .amber: return .bizarreWarning
        case .red:   return .bizarreError
        }
    }
    var shortLabel: String {
        switch self {
        case .green: return "Balanced"
        case .amber: return "Within tolerance"
        case .red:   return "Out of balance"
        }
    }
}
#endif
