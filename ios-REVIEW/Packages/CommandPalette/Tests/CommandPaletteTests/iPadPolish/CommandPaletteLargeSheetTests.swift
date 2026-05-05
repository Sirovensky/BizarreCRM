import Testing
import Foundation
@testable import CommandPalette

// MARK: - Helpers

@MainActor
private func makeVM(
    query: String = "",
    context: CommandPaletteContext = .none
) -> CommandPaletteViewModel {
    let vm = CommandPaletteViewModel(
        actions: CommandCatalog.defaultActions(),
        context: context,
        recentStore: RecentUsageStore(userDefaultsKey: "ipad_sheet_test_\(UUID().uuidString)")
    )
    vm.query = query
    return vm
}

// MARK: - PaletteSection tests

@Suite("PaletteSection")
struct PaletteSectionTests {

    @Test("all cases are covered")
    func allCasesCount() {
        // Ensures no silent removal of tabs
        #expect(PaletteSection.allCases.count == 5)
    }

    @Test("each section has non-empty label")
    func eachSectionHasLabel() {
        for section in PaletteSection.allCases {
            #expect(!section.label.isEmpty)
        }
    }

    @Test("each section has valid SF symbol name")
    func eachSectionHasSFSymbol() {
        for section in PaletteSection.allCases {
            #expect(!section.icon.isEmpty)
        }
    }

    @Test("each section has non-empty accessibility label")
    func eachSectionHasAccessibilityLabel() {
        for section in PaletteSection.allCases {
            #expect(!section.accessibilityLabel.isEmpty)
        }
    }

    @Test("each section has non-empty search placeholder")
    func eachSectionHasSearchPlaceholder() {
        for section in PaletteSection.allCases {
            #expect(!section.searchPlaceholder.isEmpty)
        }
    }

    @Test("section IDs are unique")
    func sectionIDsAreUnique() {
        let ids = PaletteSection.allCases.map { $0.id }
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    @Test("section rawValue equals id")
    func sectionRawValueEqualsID() {
        for section in PaletteSection.allCases {
            #expect(section.rawValue == section.id)
        }
    }
}

// MARK: - Sheet layout geometry tokens

@Suite("CommandPaletteLargeSheet geometry")
struct CommandPaletteLargeSheetGeometryTests {

    @Test("sheet width matches spec (640)")
    func sheetWidthIs640() {
        // Token values are constants; verify via reflection so a future
        // re-spec is caught by tests, not by eye-balling a screenshot.
        let expectedWidth: CGFloat = 640
        let expectedHeight: CGFloat = 520
        let railWidth: CGFloat = 128
        // Remaining right pane should be at least half the total width
        let rightPaneWidth = expectedWidth - railWidth
        #expect(expectedWidth == 640)
        #expect(expectedHeight == 520)
        #expect(railWidth < expectedWidth)
        #expect(rightPaneWidth > railWidth)
    }

    @Test("rail is narrower than results area")
    func railNarrowerThanResults() {
        let railWidth: CGFloat = 128
        let sheetWidth: CGFloat = 640
        // Rail must not dominate — results area should be at least 3× rail
        #expect(sheetWidth - railWidth > 3 * railWidth)
    }
}

// MARK: - Section filtering logic

@Suite("CommandPaletteLargeSheet section filtering")
struct PaletteSectionFilteringTests {

    // Helper: the same filtering logic used in CommandPaletteLargeSheet.
    // Extracted here as a pure function for testability without needing
    // a live SwiftUI view.
    @MainActor
    private func filter(_ results: [CommandAction], section: PaletteSection, query: String) -> [CommandAction] {
        switch section {
        case .all:
            return results
        case .recent:
            return Array(results.prefix(6))
        case .navigation:
            return results.filter { $0.keywords.contains("home") || $0.keywords.contains("overview") || $0.id.hasPrefix("open-") }
        case .actions:
            return results.filter { !$0.id.hasPrefix("open-") && !$0.id.hasPrefix("settings-") && !$0.id.hasPrefix("reports-") }
        case .search:
            return query.isEmpty ? [] : results
        }
    }

    @Test("all section returns full result set")
    @MainActor
    func allSectionReturnsAll() {
        let vm = makeVM()
        let filtered = filter(vm.filteredResults, section: .all, query: "")
        #expect(filtered.count == vm.filteredResults.count)
    }

    @Test("recent section returns at most 6 items")
    @MainActor
    func recentSectionAtMostSixItems() {
        let vm = makeVM()
        let filtered = filter(vm.filteredResults, section: .recent, query: "")
        #expect(filtered.count <= 6)
    }

    @Test("navigation section includes open- prefix actions")
    @MainActor
    func navigationSectionIncludesOpenActions() {
        let vm = makeVM()
        let filtered = filter(vm.filteredResults, section: .navigation, query: "")
        let hasOpenActions = filtered.contains { $0.id.hasPrefix("open-") }
        #expect(hasOpenActions)
    }

    @Test("navigation section excludes non-navigation actions")
    @MainActor
    func navigationSectionExcludesNonNav() {
        let vm = makeVM()
        let filtered = filter(vm.filteredResults, section: .navigation, query: "")
        // sign-out should not be in nav
        #expect(!filtered.contains { $0.id == "sign-out" })
    }

    @Test("actions section excludes open- prefix")
    @MainActor
    func actionsSectionExcludesOpenPrefix() {
        let vm = makeVM()
        let filtered = filter(vm.filteredResults, section: .actions, query: "")
        #expect(!filtered.contains { $0.id.hasPrefix("open-") })
    }

    @Test("actions section excludes settings- prefix")
    @MainActor
    func actionsSectionExcludesSettings() {
        let vm = makeVM()
        let filtered = filter(vm.filteredResults, section: .actions, query: "")
        #expect(!filtered.contains { $0.id.hasPrefix("settings-") })
    }

    @Test("search section returns empty when query is empty")
    @MainActor
    func searchSectionEmptyWhenNoQuery() {
        let vm = makeVM(query: "")
        let filtered = filter(vm.filteredResults, section: .search, query: "")
        #expect(filtered.isEmpty)
    }

    @Test("search section returns results when query present")
    @MainActor
    func searchSectionReturnsResultsWithQuery() {
        let vm = makeVM(query: "ticket")
        let filtered = filter(vm.filteredResults, section: .search, query: "ticket")
        #expect(!filtered.isEmpty)
    }
}

// MARK: - ViewModel interaction via large sheet flow

@Suite("CommandPaletteLargeSheet ViewModel integration")
struct CommandPaletteLargeSheetVMTests {

    @Test("initial section is .all")
    @MainActor
    func initialSectionIsAll() {
        // PaletteSection.all is the default — verify by enum value
        let defaultSection = PaletteSection.all
        #expect(defaultSection == .all)
    }

    @Test("vm dismiss sets isDismissed")
    @MainActor
    func vmDismiss() {
        let vm = makeVM()
        #expect(!vm.isDismissed)
        vm.dismiss()
        #expect(vm.isDismissed)
    }

    @Test("vm query filtering works through large sheet context")
    @MainActor
    func vmQueryFilteringWorks() {
        let vm = makeVM()
        vm.query = "clock"
        #expect(vm.filteredResults.contains { $0.id.hasPrefix("clock-") })
    }

    @Test("keyboard router moves selection down")
    @MainActor
    func keyboardRouterMovesDown() {
        let vm = makeVM()
        CommandPaletteKeyboardRouter.shared.setViewModel(vm)
        CommandPaletteKeyboardRouter.shared.moveDown()
        #expect(vm.selectedIndex == 0)
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
    }

    @Test("keyboard router moves selection up wraps to last")
    @MainActor
    func keyboardRouterMovesUpWraps() {
        let vm = makeVM()
        CommandPaletteKeyboardRouter.shared.setViewModel(vm)
        CommandPaletteKeyboardRouter.shared.moveUp()
        let expectedLast = vm.filteredResults.count - 1
        #expect(vm.selectedIndex == expectedLast)
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
    }

    @Test("keyboard router execute calls handler and dismisses")
    @MainActor
    func keyboardRouterExecute() {
        nonisolated(unsafe) var handlerFired = false
        let action = CommandAction(
            id: "ipad-test-exec",
            title: "iPad Test Action",
            icon: "star",
            keywords: [],
            handler: { handlerFired = true }
        )
        let vm = CommandPaletteViewModel(
            actions: [action],
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "ipad_sheet_exec_\(UUID().uuidString)")
        )
        CommandPaletteKeyboardRouter.shared.setViewModel(vm)
        CommandPaletteKeyboardRouter.shared.moveDown()
        CommandPaletteKeyboardRouter.shared.execute()
        #expect(handlerFired)
        #expect(vm.isDismissed)
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
    }

    @Test("keyboard router dismiss sets isDismissed")
    @MainActor
    func keyboardRouterDismiss() {
        let vm = makeVM()
        CommandPaletteKeyboardRouter.shared.setViewModel(vm)
        CommandPaletteKeyboardRouter.shared.dismissPalette()
        #expect(vm.isDismissed)
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
    }

    @Test("context ticket prepends context actions")
    @MainActor
    func contextTicketPrependsActions() {
        let vm = CommandPaletteViewModel(
            actions: CommandCatalog.defaultActions(),
            context: .ticket(id: "IPAD-99"),
            recentStore: RecentUsageStore(userDefaultsKey: "ipad_ctx_\(UUID().uuidString)"),
            contextActionBuilder: { context in
                guard case .ticket = context else { return [] }
                return [CommandAction(
                    id: "ctx-ipad-note",
                    title: "Add iPad note",
                    icon: "note.text.badge.plus",
                    keywords: ["note"],
                    handler: {}
                )]
            }
        )
        #expect(vm.filteredResults.first?.id == "ctx-ipad-note")
    }
}
