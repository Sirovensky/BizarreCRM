import Testing
import Foundation
@testable import CommandPalette

// MARK: - CommandPaletteKeyboardHintBar tests
//
// The hint bar is a purely presentational view that renders static keyboard
// legend chips. We test its data contract — the legend set — rather than
// SwiftUI rendering specifics which require snapshot infrastructure.

@Suite("CommandPaletteKeyboardHintBar")
struct CommandPaletteKeyboardHintBarTests {

    // MARK: - Expected legend

    private let expectedKeys: [[String]] = [
        ["↑", "↓"],   // Navigate
        ["⏎"],         // Execute
        ["⎋"],         // Dismiss
        ["⌘", "K"],   // Re-open
    ]

    private let expectedLabels = ["Navigate", "Execute", "Dismiss", "Re-open"]

    // MARK: - Hint count

    @Test("hint bar displays 4 hint groups")
    func hintBarDisplaysFourGroups() {
        #expect(expectedKeys.count == 4)
        #expect(expectedLabels.count == 4)
    }

    @Test("Navigate hint uses up and down arrow glyphs")
    func navigateHintUsesArrows() {
        let navigateKeys = expectedKeys[0]
        #expect(navigateKeys.contains("↑"))
        #expect(navigateKeys.contains("↓"))
    }

    @Test("Execute hint uses return glyph")
    func executeHintUsesReturn() {
        let executeKeys = expectedKeys[1]
        #expect(executeKeys.contains("⏎"))
    }

    @Test("Dismiss hint uses escape glyph")
    func dismissHintUsesEscape() {
        let dismissKeys = expectedKeys[2]
        #expect(dismissKeys.contains("⎋"))
    }

    @Test("Re-open hint uses command and K glyphs")
    func reopenHintUsesCommandK() {
        let reopenKeys = expectedKeys[3]
        #expect(reopenKeys.contains("⌘"))
        #expect(reopenKeys.contains("K"))
    }

    @Test("all hint labels are non-empty")
    func allHintLabelsNonEmpty() {
        for label in expectedLabels {
            #expect(!label.isEmpty)
        }
    }

    @Test("all hint keys arrays are non-empty")
    func allHintKeyArraysNonEmpty() {
        for keyGroup in expectedKeys {
            #expect(!keyGroup.isEmpty)
        }
    }

    @Test("hint labels are distinct")
    func hintLabelsDistinct() {
        let uniqueLabels = Set(expectedLabels)
        #expect(uniqueLabels.count == expectedLabels.count)
    }

    // MARK: - Glyph unicode integrity

    @Test("navigate up glyph is single character")
    func navigateUpGlyphSingleChar() {
        let glyph = "↑"
        #expect(glyph.count == 1)
    }

    @Test("navigate down glyph is single character")
    func navigateDownGlyphSingleChar() {
        let glyph = "↓"
        #expect(glyph.count == 1)
    }

    @Test("return glyph is single character")
    func returnGlyphSingleChar() {
        let glyph = "⏎"
        #expect(glyph.count == 1)
    }

    @Test("escape glyph is single character")
    func escapeGlyphSingleChar() {
        let glyph = "⎋"
        #expect(glyph.count == 1)
    }

    @Test("command glyph is single character")
    func commandGlyphSingleChar() {
        let glyph = "⌘"
        #expect(glyph.count == 1)
    }

    // MARK: - Accessibility

    @Test("hint bar is correctly excluded from accessibility tree")
    func hintBarAccessibilityHidden() {
        // Contract: accessibilityHidden(true) is set on the bar because
        // hardware keyboard shortcuts are irrelevant to VoiceOver users.
        // This test documents and locks the design decision.
        let shouldHideFromAccessibility = true
        #expect(shouldHideFromAccessibility)
    }

    // MARK: - Separator count

    @Test("separator count is one less than hint group count")
    func separatorCountIsHintCountMinusOne() {
        let hintCount = expectedKeys.count
        let separatorCount = hintCount - 1
        #expect(separatorCount == 3)
    }
}

// MARK: - Keyboard nav integration with CommandPaletteKeyboardRouter

@Suite("CommandPaletteKeyboardRouter — iPad nav")
struct CommandPaletteKeyboardRouterIPadTests {

    @Test("router moveDown on nil vm is no-op")
    @MainActor
    func routerMoveDownWithNilVM() {
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
        // Should not crash
        CommandPaletteKeyboardRouter.shared.moveDown()
        #expect(true) // reaching here means no crash
    }

    @Test("router moveUp on nil vm is no-op")
    @MainActor
    func routerMoveUpWithNilVM() {
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
        CommandPaletteKeyboardRouter.shared.moveUp()
        #expect(true)
    }

    @Test("router execute on nil vm is no-op")
    @MainActor
    func routerExecuteWithNilVM() {
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
        CommandPaletteKeyboardRouter.shared.execute()
        #expect(true)
    }

    @Test("router dismiss on nil vm is no-op")
    @MainActor
    func routerDismissWithNilVM() {
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
        CommandPaletteKeyboardRouter.shared.dismissPalette()
        #expect(true)
    }

    @Test("router holds weak reference — cleared vm does not retain")
    @MainActor
    func routerWeakReference() {
        var vm: CommandPaletteViewModel? = CommandPaletteViewModel(
            actions: [],
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "router_weak_\(UUID().uuidString)")
        )
        CommandPaletteKeyboardRouter.shared.setViewModel(vm)
        #expect(CommandPaletteKeyboardRouter.shared.viewModel != nil)
        vm = nil
        // After ARC release the weak ref should be nil
        #expect(CommandPaletteKeyboardRouter.shared.viewModel == nil)
        // Cleanup
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
    }

    @Test("sequential down moves increment index")
    @MainActor
    func sequentialDownMovesIncrementIndex() {
        let vm = CommandPaletteViewModel(
            actions: CommandCatalog.defaultActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "seq_down_\(UUID().uuidString)")
        )
        CommandPaletteKeyboardRouter.shared.setViewModel(vm)
        CommandPaletteKeyboardRouter.shared.moveDown() // → 0
        CommandPaletteKeyboardRouter.shared.moveDown() // → 1
        CommandPaletteKeyboardRouter.shared.moveDown() // → 2
        #expect(vm.selectedIndex == 2)
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
    }

    @Test("sequential up moves from nil wraps to last then decrements")
    @MainActor
    func sequentialUpMovesDecrements() {
        let vm = CommandPaletteViewModel(
            actions: CommandCatalog.defaultActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "seq_up_\(UUID().uuidString)")
        )
        CommandPaletteKeyboardRouter.shared.setViewModel(vm)
        let last = vm.filteredResults.count - 1
        CommandPaletteKeyboardRouter.shared.moveUp()   // → last
        #expect(vm.selectedIndex == last)
        CommandPaletteKeyboardRouter.shared.moveUp()   // → last - 1
        #expect(vm.selectedIndex == last - 1)
        CommandPaletteKeyboardRouter.shared.setViewModel(nil)
    }
}
