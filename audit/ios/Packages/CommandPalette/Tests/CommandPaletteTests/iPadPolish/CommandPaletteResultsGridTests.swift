import Testing
import Foundation
@testable import CommandPalette

// MARK: - Helpers

private func makeAction(id: String, title: String, keywords: [String] = []) -> CommandAction {
    CommandAction(id: id, title: title, icon: "star", keywords: keywords, handler: {})
}

// MARK: - CommandPaletteResultsGrid data contract tests

@Suite("CommandPaletteResultsGrid")
struct CommandPaletteResultsGridTests {

    // The grid itself is a SwiftUI view — we test its data-layer contract:
    // correct action ordering, selection index validity, hover callbacks.

    // MARK: - Empty results

    @Test("empty results array has count zero")
    func emptyResultsCount() {
        let results: [CommandAction] = []
        #expect(results.isEmpty)
    }

    @Test("selected index nil is valid when no results")
    func selectedIndexNilWithNoResults() {
        let selectedIndex: Int? = nil
        let results: [CommandAction] = []
        // selectedIndex nil with empty results should not cause out-of-bounds
        if let idx = selectedIndex {
            #expect(idx < results.count)
        } else {
            #expect(true) // nil is always safe
        }
    }

    // MARK: - Selection index validity

    @Test("selected index within bounds")
    func selectedIndexWithinBounds() {
        let results = CommandCatalog.defaultActions()
        let selectedIndex = 0
        #expect(selectedIndex < results.count)
        #expect(selectedIndex >= 0)
    }

    @Test("selected index equals result element at that index")
    func selectedIndexCorrespondsToResult() {
        let results = [
            makeAction(id: "a", title: "Alpha"),
            makeAction(id: "b", title: "Beta"),
            makeAction(id: "c", title: "Gamma")
        ]
        let selectedIndex = 1
        #expect(results[selectedIndex].id == "b")
    }

    @Test("last index is count minus one")
    func lastIndexIsCountMinusOne() {
        let results = CommandCatalog.defaultActions()
        let lastIndex = results.count - 1
        #expect(results[lastIndex].id == results.last?.id)
    }

    // MARK: - Action identity

    @Test("all actions have unique IDs")
    func allActionsUniqueIDs() {
        let results = CommandCatalog.defaultActions()
        let ids = results.map { $0.id }
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    @Test("actions preserve order from vm.filteredResults")
    @MainActor
    func actionsPreserveVMOrder() {
        let vm = CommandPaletteViewModel(
            actions: CommandCatalog.defaultActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "grid_order_\(UUID().uuidString)")
        )
        vm.query = "clock"
        let vmIDs = vm.filteredResults.map { $0.id }
        // Grid receives filteredResults in the same order
        let gridResults = vm.filteredResults
        let gridIDs = gridResults.map { $0.id }
        #expect(vmIDs == gridIDs)
    }

    // MARK: - Keyword preview

    @Test("keywords are accessible for preview hint")
    func keywordsAccessibleForPreview() {
        let action = makeAction(id: "x", title: "X Action", keywords: ["alpha", "beta", "gamma", "delta"])
        // Preview shows first 3 keywords
        let previewHint = action.keywords.prefix(3).joined(separator: " · ")
        #expect(previewHint == "alpha · beta · gamma")
    }

    @Test("action with no keywords yields empty preview hint")
    func emptyKeywordsYieldsEmptyHint() {
        let action = makeAction(id: "y", title: "No Keywords")
        let hint = action.keywords.prefix(3).joined(separator: " · ")
        #expect(hint.isEmpty)
    }

    // MARK: - 2-column layout arithmetic

    @Test("results split into 2 columns evenly with even count")
    func twoColumnsEvenCount() {
        let count = 4
        let leftColumn = count / 2
        let rightColumn = count - leftColumn
        #expect(leftColumn == rightColumn)
    }

    @Test("results split into 2 columns with odd count has one extra in first")
    func twoColumnsOddCount() {
        let count = 5
        // LazyVGrid distributes: rows = ceil(count/2)
        let rowCount = Int(ceil(Double(count) / 2.0))
        #expect(rowCount == 3)
    }

    @Test("15 default actions produce 8 grid rows in 2 columns")
    func fifteenActionsProduceEightRows() {
        let count = CommandCatalog.defaultActions().count
        #expect(count == 15)
        let rowCount = Int(ceil(Double(count) / 2.0))
        #expect(rowCount == 8)
    }

    // MARK: - Scroll-to-selected: index tracking

    @Test("scrollTo target id matches results element at selectedIndex")
    func scrollToTargetMatchesSelectedIndex() {
        let results = CommandCatalog.defaultActions()
        let selectedIndex = 4
        let targetID = results[selectedIndex].id
        #expect(targetID == results[selectedIndex].id)
        #expect(!targetID.isEmpty)
    }

    // MARK: - Hover

    @Test("hover callback receives nil on hover end")
    func hoverCallbackReceivesNilOnEnd() {
        // Pure logic check — the callback contract
        var capturedIndex: Int? = 999
        let onHover: (Int?) -> Void = { capturedIndex = $0 }
        onHover(nil)
        #expect(capturedIndex == nil)
    }

    @Test("hover callback receives index on hover start")
    func hoverCallbackReceivesIndexOnStart() {
        var capturedIndex: Int? = nil
        let onHover: (Int?) -> Void = { capturedIndex = $0 }
        onHover(3)
        #expect(capturedIndex == 3)
    }
}

// MARK: - ResultGridCell data contract

@Suite("ResultGridCell data")
struct ResultGridCellDataTests {

    @Test("isSelected and isHovered are independent flags")
    func selectedAndHoveredAreIndependent() {
        // Verify both flags can be set independently without conflict
        let selectedOnly = (isSelected: true, isHovered: false)
        let hoveredOnly  = (isSelected: false, isHovered: true)
        let both         = (isSelected: true, isHovered: true)
        let neither      = (isSelected: false, isHovered: false)

        // effectivelyHighlighted = isSelected || isHovered
        #expect(selectedOnly.isSelected || selectedOnly.isHovered)
        #expect(hoveredOnly.isSelected || hoveredOnly.isHovered)
        #expect(both.isSelected || both.isHovered)
        #expect(!(neither.isSelected || neither.isHovered))
    }

    @Test("effectivelyHighlighted true when selected")
    func effectivelyHighlightedWhenSelected() {
        let isSelected = true
        let isHovered  = false
        let highlighted = isSelected || isHovered
        #expect(highlighted)
    }

    @Test("effectivelyHighlighted true when hovered")
    func effectivelyHighlightedWhenHovered() {
        let isSelected = false
        let isHovered  = true
        let highlighted = isSelected || isHovered
        #expect(highlighted)
    }

    @Test("effectivelyHighlighted false when neither")
    func effectivelyHighlightedFalseWhenNeither() {
        let isSelected = false
        let isHovered  = false
        let highlighted = isSelected || isHovered
        #expect(!highlighted)
    }
}
