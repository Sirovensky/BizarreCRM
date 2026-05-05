import Foundation

// MARK: - CommandPaletteMarkovHinter

/// Suggests the most likely next command based on first-order Markov pair frequencies.
///
/// The hinter is a **pure function** over its stored pair table — given the same
/// `lastID` and the same `pairFrequencies`, it always returns the same result.
/// No side-effectful I/O is performed inside this type.
///
/// ## Usage
/// ```swift
/// var hinter = CommandPaletteMarkovHinter()
/// hinter.recordTransition(from: "clock-in", to: "open-tickets")
/// hinter.recordTransition(from: "clock-in", to: "open-tickets")
/// hinter.recordTransition(from: "clock-in", to: "open-dashboard")
///
/// let next = hinter.suggest(after: "clock-in", topK: 2)
/// // → ["open-tickets", "open-dashboard"]
/// ```
///
/// ## Seeding
/// Pass a pre-built `pairFrequencies` dictionary to reproduce a deterministic
/// suggestion set in tests or previews:
/// ```swift
/// let seeded = CommandPaletteMarkovHinter(pairFrequencies: ["a": ["b": 5, "c": 1]])
/// ```
///
/// ## Immutability
/// `recordTransition` returns a *new* `CommandPaletteMarkovHinter` instead of
/// mutating in place, satisfying the project immutability requirement.
public struct CommandPaletteMarkovHinter: Sendable {

    // MARK: - Storage
    //
    // pairFrequencies["A"]["B"] = count of times B was executed directly after A.

    public let pairFrequencies: [String: [String: Int]]

    // MARK: - Init

    /// Creates an empty hinter with no recorded transitions.
    public init() {
        self.pairFrequencies = [:]
    }

    /// Creates a hinter pre-loaded with `pairFrequencies`.
    /// Useful for seeding tests and previews.
    public init(pairFrequencies: [String: [String: Int]]) {
        self.pairFrequencies = pairFrequencies
    }

    // MARK: - Recording (returns new value — immutable update)

    /// Returns a *new* `CommandPaletteMarkovHinter` with the transition
    /// from → to incremented by one.
    ///
    /// - Parameters:
    ///   - from: The command that was just executed.
    ///   - to:   The command that was executed next.
    /// - Returns: Updated hinter (caller must replace the old instance).
    public func recordingTransition(from: String, to: String) -> CommandPaletteMarkovHinter {
        var updated = pairFrequencies
        var successors = updated[from] ?? [:]
        successors[to, default: 0] += 1
        updated[from] = successors
        return CommandPaletteMarkovHinter(pairFrequencies: updated)
    }

    // MARK: - Suggestion (pure function)

    /// Returns up to `topK` successor action IDs sorted by descending frequency.
    ///
    /// Returns an empty array if:
    /// - `lastID` has no recorded successors.
    /// - `topK` is zero.
    ///
    /// - Parameters:
    ///   - lastID: The most recently executed command ID.
    ///   - topK:   Maximum number of suggestions to return. Defaults to 3.
    /// - Returns:  Action IDs in descending likelihood order.
    public func suggest(after lastID: String, topK: Int = 3) -> [String] {
        guard topK > 0, let successors = pairFrequencies[lastID], !successors.isEmpty else {
            return []
        }
        return successors
            .sorted { $0.value > $1.value }
            .prefix(topK)
            .map { $0.key }
    }

    /// Resolve suggestions to full `CommandAction` values from a catalog.
    ///
    /// IDs that no longer exist in the catalog are silently dropped.
    ///
    /// - Parameters:
    ///   - lastID:  Most recently executed command ID.
    ///   - catalog: All available actions.
    ///   - topK:    Maximum number of suggestions. Defaults to 3.
    /// - Returns:   Resolved actions in descending likelihood order.
    public func suggestActions(
        after lastID: String,
        catalog: [CommandAction],
        topK: Int = 3
    ) -> [CommandAction] {
        let ids = suggest(after: lastID, topK: topK)
        let index = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return ids.compactMap { index[$0] }
    }
}
