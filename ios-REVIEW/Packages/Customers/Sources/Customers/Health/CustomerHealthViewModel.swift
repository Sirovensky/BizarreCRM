import Foundation
import Observation
import Core

// MARK: - CustomerHealthViewModel

/// Drives `CustomerHealthView`.
///
/// Loads `CustomerHealthSnapshot` via a `CustomerHealthRepository` on `task`.
/// Exposes a `recalculate()` action for manager/admin CTAs.
///
/// Thread safety: `@MainActor` + `@Observable` — all mutations happen on the main actor.
@MainActor
@Observable
public final class CustomerHealthViewModel {
    // MARK: - State

    public private(set) var snapshot: CustomerHealthSnapshot?
    public private(set) var isLoading: Bool = false
    public private(set) var isRecalculating: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var recalcMessage: String?

    // MARK: - Init

    private let repo: CustomerHealthRepository
    private let customerId: Int64

    public init(repo: CustomerHealthRepository, customerId: Int64) {
        self.repo       = repo
        self.customerId = customerId
    }

    // MARK: - Actions

    /// Loads the health snapshot. Safe to call from `.task {}`.
    public func load() async {
        guard !isLoading else { return }
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await repo.healthSnapshot(customerId: customerId)
        } catch {
            AppLog.ui.error("CustomerHealth load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Triggers a server-side RFM recomputation.
    /// Does nothing if already in flight.
    public func recalculate() async {
        guard !isRecalculating else { return }
        isRecalculating = true
        recalcMessage   = nil
        defer { isRecalculating = false }

        do {
            snapshot      = try await repo.recalculate(customerId: customerId)
            recalcMessage = "Score updated."
        } catch {
            AppLog.ui.error("CustomerHealth recalc failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not update score: \(error.localizedDescription)"
        }
    }

    // MARK: - Derived helpers

    /// Health score to display — falls back to 0 when not loaded.
    public var displayScore: Int {
        snapshot?.score.value ?? 0
    }

    /// True when the score is loaded and non-trivial.
    public var hasData: Bool {
        snapshot != nil
    }
}
