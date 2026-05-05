import Foundation
import Observation

// MARK: - Party model

/// One seat at the split-check table.
public struct SplitParty: Identifiable, Equatable, Sendable {
    public let id:    PartyID
    public var label: String   // e.g. "Guest 1", "Alice"
    public var paidCents: Int

    public init(id: PartyID = UUID(), label: String, paidCents: Int = 0) {
        self.id         = id
        self.label      = label
        self.paidCents  = paidCents
    }
}

// MARK: - SplitCheckViewModel

/// §16.13 — @Observable VM for the split-check overlay. Manages parties,
/// line assignments (by-item mode), custom amounts, and payment progress.
/// All money in cents.
@MainActor
@Observable
public final class SplitCheckViewModel {

    // MARK: Published state

    public private(set) var mode: SplitCheckMode
    public private(set) var parties: [SplitParty]
    /// By-item assignments: CartLineID → PartyID.
    public private(set) var assignments: [CartLineID: PartyID] = [:]
    /// Custom amounts per party (custom mode only).
    public private(set) var customAmounts: [PartyID: Int] = [:]
    public private(set) var validationErrors: [SplitError] = []

    // MARK: Init

    /// - Parameters:
    ///   - mode:       Starting split mode.
    ///   - partyCount: Number of parties (≥2; clamped to 2 if lower).
    ///   - totalCents: Cart grand total. Used for even split preview.
    public init(mode: SplitCheckMode = .evenly, partyCount: Int = 2, totalCents: Int = 0) {
        self.mode = mode
        let count = max(2, partyCount)
        self.parties = (1...count).map {
            SplitParty(label: "Guest \($0)")
        }
        self._totalCents = totalCents
    }

    // MARK: Private

    private var _totalCents: Int

    // MARK: - Derived

    /// Per-party owed amounts (cents) based on current mode.
    public var partyOwedCents: [PartyID: Int] {
        switch mode {
        case .evenly:
            let buckets = SplitCheckCalculator.even(totalCents: _totalCents, parties: parties.count)
            return Dictionary(uniqueKeysWithValues: zip(parties.map(\.id), buckets))

        case .byLineItem:
            return [:]  // View drives per-party display from `assignments`.

        case .custom:
            return customAmounts
        }
    }

    public var totalPaidCents: Int {
        parties.map(\.paidCents).reduce(0, +)
    }

    public var remainingCents: Int {
        max(0, _totalCents - totalPaidCents)
    }

    public var allPartiesPaid: Bool {
        remainingCents == 0 && totalPaidCents > 0
    }

    // MARK: - Mutations

    public func setMode(_ newMode: SplitCheckMode) {
        mode = newMode
        validationErrors = []
    }

    public func addParty(label: String? = nil) {
        let idx   = parties.count + 1
        let party = SplitParty(label: label ?? "Guest \(idx)")
        parties   = parties + [party]
    }

    public func removeParty(id: PartyID) {
        guard parties.count > 2 else { return }  // minimum 2
        parties     = parties.filter { $0.id != id }
        assignments = assignments.filter { $0.value != id }
        customAmounts.removeValue(forKey: id)
    }

    public func renameParty(id: PartyID, label: String) {
        parties = parties.map { $0.id == id ? SplitParty(id: $0.id, label: label, paidCents: $0.paidCents) : $0 }
    }

    /// Assign a cart line to a party (by-item mode).
    public func assign(lineId: CartLineID, to partyId: PartyID) {
        assignments = assignments.merging([lineId: partyId]) { _, new in new }
    }

    public func unassign(lineId: CartLineID) {
        assignments.removeValue(forKey: lineId)
    }

    /// Set the amount a specific party has tendered/paid.
    public func recordPayment(partyId: PartyID, amountCents: Int) {
        parties = parties.map {
            $0.id == partyId
                ? SplitParty(id: $0.id, label: $0.label, paidCents: max(0, amountCents))
                : $0
        }
    }

    public func setCustomAmount(partyId: PartyID, cents: Int) {
        customAmounts = customAmounts.merging([partyId: max(0, cents)]) { _, new in new }
    }

    /// Run validation (by-item mode only). Returns errors also stored in `validationErrors`.
    @discardableResult
    public func validate(lines: [any CartLine]) -> [SplitError] {
        guard mode == .byLineItem else {
            validationErrors = []
            return []
        }
        let cartLines = lines.map { AnyCartLine($0) }
        let errors = SplitCheckCalculator.validate(
            lines: cartLines,
            assignments: assignments,
            totalCents: _totalCents
        )
        validationErrors = errors
        return errors
    }
}

// MARK: - Type-erased CartLine for heterogeneous arrays

struct AnyCartLine: CartLine {
    let id: CartLineID
    let subtotalCents: Int

    init(_ base: any CartLine) {
        self.id            = base.id
        self.subtotalCents = base.subtotalCents
    }
}
