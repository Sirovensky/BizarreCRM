import Foundation

/// §16.13 — How the cashier wants to split the bill.
public enum SplitCheckMode: String, Sendable, Equatable, CaseIterable {
    /// Each party claims specific line items.
    case byLineItem
    /// Divide total evenly among N parties (last party absorbs rounding remainder).
    case evenly
    /// Cashier enters arbitrary cent amounts per party.
    case custom
}

/// Stable identifier types used by SplitCheck.
public typealias CartLineID = UUID
public typealias PartyID    = UUID

/// Validation errors produced by `SplitCheckCalculator.validate`.
public enum SplitError: Error, Equatable, Sendable {
    case unassignedLines(count: Int)
    case partyTotalMismatch(partyId: PartyID, expected: Int, got: Int)
    case sumMismatch(expected: Int, got: Int)
    case noParties
}
