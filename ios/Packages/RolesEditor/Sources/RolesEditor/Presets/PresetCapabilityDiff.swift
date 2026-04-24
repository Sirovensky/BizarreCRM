import Foundation

// MARK: - PresetCapabilityDiff
//
// §47 Roles Capability Presets — pure value snapshot of what applying a
// preset would change relative to a role's current capabilities.

/// Immutable snapshot of the delta between a current role's capabilities
/// and a target preset's capabilities.
///
/// - `added`: capabilities the preset grants that the role does not currently have.
/// - `removed`: capabilities the role currently has that the preset does not include.
public struct PresetCapabilityDiff: Sendable, Equatable {

    // MARK: Stored properties

    public let added: Set<String>
    public let removed: Set<String>

    // MARK: Init

    public init(added: Set<String>, removed: Set<String>) {
        self.added = added
        self.removed = removed
    }

    // MARK: Derived helpers

    /// True when the preset exactly matches the current capability set.
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    /// Total number of changes (additions + removals).
    public var changeCount: Int { added.count + removed.count }

    /// Sorted capability ids that will be added, for deterministic display.
    public var sortedAdded: [String] { added.sorted() }

    /// Sorted capability ids that will be removed, for deterministic display.
    public var sortedRemoved: [String] { removed.sorted() }
}
