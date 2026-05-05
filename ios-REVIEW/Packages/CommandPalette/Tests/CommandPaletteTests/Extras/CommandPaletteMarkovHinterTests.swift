import Testing
import Foundation
@testable import CommandPalette

// MARK: - CommandPaletteMarkovHinterTests

@Suite("CommandPaletteMarkovHinter")
struct CommandPaletteMarkovHinterTests {

    // MARK: - Initial state

    @Test("Empty hinter returns no suggestions")
    func emptyHinterReturnsNoSuggestions() {
        let hinter = CommandPaletteMarkovHinter()
        #expect(hinter.suggest(after: "new-ticket").isEmpty)
    }

    @Test("Suggest with topK zero returns empty")
    func suggestTopKZeroReturnsEmpty() {
        let hinter = CommandPaletteMarkovHinter(pairFrequencies: ["a": ["b": 3]])
        #expect(hinter.suggest(after: "a", topK: 0).isEmpty)
    }

    @Test("Unknown lastID returns empty")
    func unknownLastIDReturnsEmpty() {
        let hinter = CommandPaletteMarkovHinter(pairFrequencies: ["a": ["b": 1]])
        #expect(hinter.suggest(after: "z").isEmpty)
    }

    // MARK: - Transition recording (immutable update)

    @Test("recordingTransition returns new instance with incremented count")
    func recordingTransitionReturnsNewInstance() {
        let original = CommandPaletteMarkovHinter()
        let updated = original.recordingTransition(from: "clock-in", to: "open-tickets")

        // Original is unchanged
        #expect(original.pairFrequencies.isEmpty)

        // Updated has the transition
        #expect(updated.pairFrequencies["clock-in"]?["open-tickets"] == 1)
    }

    @Test("Multiple transitions accumulate counts")
    func multipleTransitionsAccumulateCounts() {
        var hinter = CommandPaletteMarkovHinter()
        hinter = hinter.recordingTransition(from: "A", to: "B")
        hinter = hinter.recordingTransition(from: "A", to: "B")
        hinter = hinter.recordingTransition(from: "A", to: "C")

        #expect(hinter.pairFrequencies["A"]?["B"] == 2)
        #expect(hinter.pairFrequencies["A"]?["C"] == 1)
    }

    @Test("Different from-IDs are stored independently")
    func differentFromIDsAreIndependent() {
        var hinter = CommandPaletteMarkovHinter()
        hinter = hinter.recordingTransition(from: "A", to: "X")
        hinter = hinter.recordingTransition(from: "B", to: "X")

        #expect(hinter.pairFrequencies["A"]?["X"] == 1)
        #expect(hinter.pairFrequencies["B"]?["X"] == 1)
    }

    // MARK: - Suggestions ordered by frequency

    @Test("Suggestions are ordered descending by frequency")
    func suggestionsOrderedByFrequency() {
        let hinter = CommandPaletteMarkovHinter(pairFrequencies: [
            "start": ["A": 1, "B": 5, "C": 3]
        ])

        let result = hinter.suggest(after: "start", topK: 3)
        #expect(result == ["B", "C", "A"])
    }

    @Test("topK limits number of suggestions")
    func topKLimitsSuggestions() {
        let hinter = CommandPaletteMarkovHinter(pairFrequencies: [
            "start": ["A": 4, "B": 3, "C": 2, "D": 1]
        ])

        let result = hinter.suggest(after: "start", topK: 2)
        #expect(result.count == 2)
        #expect(result.first == "A")
        #expect(result.last == "B")
    }

    @Test("Suggest returns all successors when topK exceeds count")
    func suggestLargeTopKReturnAll() {
        let hinter = CommandPaletteMarkovHinter(pairFrequencies: [
            "x": ["y": 2]
        ])
        let result = hinter.suggest(after: "x", topK: 100)
        #expect(result == ["y"])
    }

    // MARK: - Seeded hinter (deterministic)

    @Test("Seeded hinter produces deterministic suggestions")
    func seededHinterDeterministic() {
        let seed: [String: [String: Int]] = [
            "clock-in": ["open-tickets": 10, "open-dashboard": 3, "new-ticket": 1]
        ]
        let h1 = CommandPaletteMarkovHinter(pairFrequencies: seed)
        let h2 = CommandPaletteMarkovHinter(pairFrequencies: seed)

        #expect(h1.suggest(after: "clock-in") == h2.suggest(after: "clock-in"))
    }

    // MARK: - suggestActions resolves to CommandAction values

    @Test("suggestActions returns resolved CommandAction values")
    func suggestActionsResolvesActions() {
        let catalog = [
            CommandAction(id: "open-tickets", title: "Open Tickets", icon: "list.bullet", handler: {}),
            CommandAction(id: "open-dashboard", title: "Open Dashboard", icon: "gauge", handler: {}),
            CommandAction(id: "new-ticket", title: "New Ticket", icon: "ticket", handler: {})
        ]

        let hinter = CommandPaletteMarkovHinter(pairFrequencies: [
            "clock-in": ["open-tickets": 5, "open-dashboard": 2]
        ])

        let result = hinter.suggestActions(after: "clock-in", catalog: catalog)
        #expect(result.count == 2)
        #expect(result[0].id == "open-tickets")
        #expect(result[1].id == "open-dashboard")
    }

    @Test("suggestActions drops IDs missing from catalog")
    func suggestActionsDropsMissingIDs() {
        let catalog = [
            CommandAction(id: "open-tickets", title: "Open Tickets", icon: "list.bullet", handler: {})
        ]

        let hinter = CommandPaletteMarkovHinter(pairFrequencies: [
            "X": ["open-tickets": 3, "ghost-action": 10]
        ])

        let result = hinter.suggestActions(after: "X", catalog: catalog)
        #expect(result.count == 1)
        #expect(result[0].id == "open-tickets")
    }

    // MARK: - Chain of transitions

    @Test("Full session chain builds correct pair table")
    func fullSessionChain() {
        let session = ["A", "B", "C", "B", "A", "B"]
        var hinter = CommandPaletteMarkovHinter()
        for i in 0..<session.count - 1 {
            hinter = hinter.recordingTransition(from: session[i], to: session[i + 1])
        }

        // A→B appeared twice
        #expect(hinter.pairFrequencies["A"]?["B"] == 2)
        // B→C appeared once
        #expect(hinter.pairFrequencies["B"]?["C"] == 1)
        // C→B appeared once
        #expect(hinter.pairFrequencies["C"]?["B"] == 1)
        // B→A appeared once
        #expect(hinter.pairFrequencies["B"]?["A"] == 1)

        let topAfterA = hinter.suggest(after: "A", topK: 1)
        #expect(topAfterA == ["B"])
    }
}
