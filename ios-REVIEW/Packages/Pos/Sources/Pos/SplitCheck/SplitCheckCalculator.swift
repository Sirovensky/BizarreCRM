import Foundation

/// §16.13 — Pure, testable split-check math. Zero side-effects, no imports
/// of UIKit or Observation. All money in cents (Int).
public enum SplitCheckCalculator {

    // MARK: - Even split

    /// Divide `totalCents` evenly across `parties`. The last bucket absorbs
    /// any rounding remainder so `result.reduce(0, +) == totalCents`.
    ///
    /// - Returns: Array of `parties` Int values, one per party.
    ///   Returns `[totalCents]` when `parties <= 1`.
    public static func even(totalCents: Int, parties: Int) -> [Int] {
        guard parties > 1 else { return [totalCents] }
        let base      = totalCents / parties
        let remainder = totalCents % parties
        var buckets   = [Int](repeating: base, count: parties)
        buckets[parties - 1] += remainder
        return buckets
    }

    // MARK: - By-line-item split

    /// Accumulate line totals per party based on `assignments`.
    ///
    /// - Parameters:
    ///   - lines:       Cart lines (each carries `lineSubtotalCents`).
    ///   - assignments: Map from `CartLineID` → `PartyID`. Unassigned lines
    ///                  are ignored (caller should validate first).
    /// - Returns: Dictionary of `PartyID` → total cents for that party.
    public static func byLineItem(
        lines: [CartLine],
        assignments: [CartLineID: PartyID]
    ) -> [PartyID: Int] {
        var result: [PartyID: Int] = [:]
        for line in lines {
            guard let partyId = assignments[line.id] else { continue }
            result[partyId, default: 0] += line.subtotalCents
        }
        return result
    }

    // MARK: - Validation

    /// Validate that a by-line-item split is self-consistent.
    ///
    /// Rules checked:
    /// 1. At least one party exists.
    /// 2. No unassigned lines (every `CartLine` has a mapping in `assignments`).
    /// 3. Party sums equal `totalCents` in aggregate.
    ///
    /// - Returns: Array of `SplitError`. Empty means the split is valid.
    public static func validate(
        lines: [CartLine],
        assignments: [CartLineID: PartyID],
        totalCents: Int
    ) -> [SplitError] {
        var errors: [SplitError] = []

        // Rule 1: Need at least one party.
        let partyIds = Set(assignments.values)
        if partyIds.isEmpty {
            errors.append(.noParties)
            return errors  // nothing else meaningful to check
        }

        // Rule 2: All lines must be assigned.
        let unassigned = lines.filter { assignments[$0.id] == nil }.count
        if unassigned > 0 {
            errors.append(.unassignedLines(count: unassigned))
        }

        // Rule 3: Party totals sum to totalCents.
        let totals = byLineItem(lines: lines, assignments: assignments)
        let sum    = totals.values.reduce(0, +)
        if sum != totalCents {
            errors.append(.sumMismatch(expected: totalCents, got: sum))
        }

        return errors
    }
}

// MARK: - CartLine protocol

/// Minimal projection of a cart line that `SplitCheckCalculator` needs.
/// Keeping it protocol-based lets us use `CartItem` directly and write
/// tests with lightweight fakes.
public protocol CartLine: Sendable {
    var id: CartLineID { get }
    var subtotalCents: Int { get }
}

extension CartItem: CartLine {
    public var subtotalCents: Int { lineSubtotalCents }
}
