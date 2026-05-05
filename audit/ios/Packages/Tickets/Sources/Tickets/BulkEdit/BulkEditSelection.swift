import Foundation
import Observation

// MARK: - BulkEditSelection

/// Observable tracker for the set of ticket IDs currently selected for
/// bulk editing. Attach one instance to the list view as `@State` and
/// share via the environment or direct init.
///
/// All mutations return a **new** value rather than mutating in-place where
/// the API exposes a snapshot; the underlying `Set` is replaced atomically
/// so observers always see a consistent value.
@MainActor
@Observable
public final class BulkEditSelection: Sendable {

    // MARK: - State

    /// The currently selected ticket IDs.
    public private(set) var selectedIDs: Set<Int64> = []

    /// Whether bulk-selection mode is active (the UI should show checkmarks).
    public private(set) var isActive: Bool = false

    // MARK: - Derived

    /// Number of selected tickets.
    public var count: Int { selectedIDs.count }

    /// True when at least one ticket is selected.
    public var hasSelection: Bool { !selectedIDs.isEmpty }

    // MARK: - Init

    public init() {}

    // MARK: - Selection mutations

    /// Toggle selection mode on/off. Clears selection when deactivating.
    public func toggleMode() {
        if isActive {
            isActive = false
            selectedIDs = []
        } else {
            isActive = true
        }
    }

    /// Activate selection mode explicitly (e.g. on long-press).
    public func activateMode() {
        isActive = true
    }

    /// Deactivate mode and clear selection.
    public func deactivate() {
        isActive = false
        selectedIDs = []
    }

    /// Toggle a single ticket in/out of the selection set.
    public func toggle(_ id: Int64) {
        var next = selectedIDs
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        selectedIDs = next
    }

    /// Select every ID in the supplied list.
    public func selectAll(_ ids: [Int64]) {
        selectedIDs = Set(ids)
    }

    /// Clear the entire selection without deactivating mode.
    public func clearAll() {
        selectedIDs = []
    }

    /// Replace the entire selection with a new set (immutable swap).
    public func replace(with ids: Set<Int64>) {
        selectedIDs = ids
    }
}
