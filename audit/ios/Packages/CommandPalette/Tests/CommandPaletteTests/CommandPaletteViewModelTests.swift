import Testing
import Foundation
@testable import CommandPalette

// MARK: - Helpers

private func makeActions() -> [CommandAction] {
    [
        CommandAction(
            id: "new-ticket",
            title: "New Ticket",
            icon: "ticket",
            keywords: ["create", "repair", "job"],
            handler: {}
        ),
        CommandAction(
            id: "new-customer",
            title: "New Customer",
            icon: "person.badge.plus",
            keywords: ["add", "client"],
            handler: {}
        ),
        CommandAction(
            id: "find-customer-phone",
            title: "Find Customer by Phone",
            icon: "phone.fill",
            keywords: ["search", "lookup", "mobile"],
            handler: {}
        ),
        CommandAction(
            id: "open-dashboard",
            title: "Open Dashboard",
            icon: "gauge",
            keywords: ["home", "overview"],
            handler: {}
        ),
        CommandAction(
            id: "clock-in",
            title: "Clock In",
            icon: "clock.badge.checkmark",
            keywords: ["timeclock", "start", "shift"],
            handler: {}
        ),
        CommandAction(
            id: "clock-out",
            title: "Clock Out",
            icon: "clock.badge.xmark",
            keywords: ["timeclock", "end", "shift"],
            handler: {}
        ),
        CommandAction(
            id: "settings-tax",
            title: "Settings: Tax",
            icon: "percent",
            keywords: ["tax", "vat", "config"],
            handler: {}
        )
    ]
}

@Suite("CommandPaletteViewModel")
struct CommandPaletteViewModelTests {

    // MARK: - Initial state

    @Test("initial query is empty")
    @MainActor
    func initialQueryEmpty() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        #expect(vm.query.isEmpty)
    }

    @Test("initial results show all actions")
    @MainActor
    func initialResultsAll() {
        let actions = makeActions()
        let vm = CommandPaletteViewModel(
            actions: actions,
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        // With empty query all actions should be present (ordered by recent then title)
        #expect(vm.filteredResults.count == actions.count)
    }

    // MARK: - Filtering

    @Test("filter by query returns matching results")
    @MainActor
    func filterByQueryMatchesResults() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.query = "ticket"
        #expect(vm.filteredResults.contains { $0.id == "new-ticket" })
    }

    @Test("filter excludes non-matching results")
    @MainActor
    func filterExcludesNonMatches() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.query = "zzz"
        #expect(vm.filteredResults.isEmpty)
    }

    @Test("filter searches in keywords too")
    @MainActor
    func filterSearchesKeywords() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.query = "repair"
        #expect(vm.filteredResults.contains { $0.id == "new-ticket" })
    }

    // MARK: - Selection navigation

    @Test("initially no selection")
    @MainActor
    func initialNoSelection() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        #expect(vm.selectedIndex == nil)
    }

    @Test("move down sets selection to 0")
    @MainActor
    func moveDownSetsIndexToZero() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.moveSelectionDown()
        #expect(vm.selectedIndex == 0)
    }

    @Test("move down increments selection")
    @MainActor
    func moveDownIncrements() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.moveSelectionDown()
        vm.moveSelectionDown()
        #expect(vm.selectedIndex == 1)
    }

    @Test("move up from nil wraps to last")
    @MainActor
    func moveUpFromNilWrapsToLast() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.moveSelectionUp()
        let expected = vm.filteredResults.count - 1
        #expect(vm.selectedIndex == expected)
    }

    @Test("move down wraps from last to nil")
    @MainActor
    func moveDownWrapsFromLastToNil() {
        let actions = makeActions()
        let vm = CommandPaletteViewModel(
            actions: actions,
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        // Go to end
        for _ in 0..<actions.count {
            vm.moveSelectionDown()
        }
        // One more wraps back
        vm.moveSelectionDown()
        #expect(vm.selectedIndex == nil)
    }

    // MARK: - Execute

    @Test("execute selected action calls handler")
    @MainActor
    func executeCallsHandler() {
        nonisolated(unsafe) var called = false
        let action = CommandAction(
            id: "test-action",
            title: "Test Action",
            icon: "star",
            keywords: [],
            handler: { called = true }
        )
        let vm = CommandPaletteViewModel(
            actions: [action],
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.moveSelectionDown()
        vm.executeSelected()
        #expect(called)
    }

    @Test("execute records usage in recent store")
    @MainActor
    func executeRecordsUsage() {
        let store = RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        let action = CommandAction(
            id: "my-action",
            title: "My Action",
            icon: "star",
            keywords: [],
            handler: {}
        )
        let vm = CommandPaletteViewModel(
            actions: [action],
            context: .none,
            recentStore: store
        )
        vm.moveSelectionDown()
        vm.executeSelected()
        #expect(store.recentIDs.contains("my-action"))
    }

    @Test("execute with no selection is a no-op")
    @MainActor
    func executeWithNoSelectionIsNoop() {
        nonisolated(unsafe) var called = false
        let action = CommandAction(
            id: "test-action",
            title: "Test Action",
            icon: "star",
            keywords: [],
            handler: { called = true }
        )
        let vm = CommandPaletteViewModel(
            actions: [action],
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        // Do NOT move selection
        vm.executeSelected()
        #expect(!called)
    }

    // MARK: - Recent-usage boost

    @Test("recently used action ranks higher with empty query")
    @MainActor
    func recentActionRanksHigherEmptyQuery() {
        let store = RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        store.record(id: "clock-in")
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: store
        )
        #expect(vm.filteredResults.first?.id == "clock-in")
    }

    // MARK: - Context actions

    @Test("ticket context prepends context-specific actions")
    @MainActor
    func ticketContextPrependsActions() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .ticket(id: "1234"),
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)"),
            contextActionBuilder: { context in
                switch context {
                case .ticket:
                    return [CommandAction(
                        id: "ctx-add-note",
                        title: "Add note to ticket",
                        icon: "note.text.badge.plus",
                        keywords: ["note", "comment"],
                        handler: {}
                    )]
                default:
                    return []
                }
            }
        )
        let ids = vm.filteredResults.map { $0.id }
        #expect(ids.contains("ctx-add-note"))
        // Context actions appear first
        #expect(ids.first == "ctx-add-note")
    }

    @Test("no context yields no context actions")
    @MainActor
    func noContextYieldsNoContextActions() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        #expect(!vm.filteredResults.map { $0.id }.contains("ctx-add-note"))
    }

    // MARK: - Dismiss

    @Test("dismiss sets isDismissed to true")
    @MainActor
    func dismissSetsDismissed() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        #expect(!vm.isDismissed)
        vm.dismiss()
        #expect(vm.isDismissed)
    }

    // MARK: - Entity detection

    @Test("ticket number pattern detected")
    @MainActor
    func ticketPatternDetected() {
        let vm = CommandPaletteViewModel(
            actions: [],
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.query = "#1234"
        let suggestion = vm.entitySuggestion
        if case .ticket(let id) = suggestion {
            #expect(id == "1234")
        } else {
            Issue.record("Expected ticket entity suggestion for '#1234', got \(String(describing: suggestion))")
        }
    }

    @Test("phone number pattern detected")
    @MainActor
    func phonePatternDetected() {
        let vm = CommandPaletteViewModel(
            actions: [],
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.query = "555-867-5309"
        let suggestion = vm.entitySuggestion
        if case .phone(let number) = suggestion {
            #expect(!number.isEmpty)
        } else {
            Issue.record("Expected phone entity suggestion, got \(String(describing: suggestion))")
        }
    }

    @Test("no pattern gives nil entity suggestion")
    @MainActor
    func noPatternGivesNilSuggestion() {
        let vm = CommandPaletteViewModel(
            actions: makeActions(),
            context: .none,
            recentStore: RecentUsageStore(userDefaultsKey: "vm_test_\(UUID().uuidString)")
        )
        vm.query = "ticket"
        #expect(vm.entitySuggestion == nil)
    }
}
