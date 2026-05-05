import Testing
import SwiftUI
@testable import Settings

// MARK: - SettingsThreeColumnShell logic tests
//
// The shell is a SwiftUI View; its rendering cannot be exercised in a headless
// test target.  These tests cover the pure-logic layer it delegates to:
// SettingsSectionGroups (sections data) and SettingsSearchViewModel
// (search coordination), plus the `resolvePageID` mapping helper that is
// exposed indirectly through SettingsEntry.path conventions.

@Suite("SettingsThreeColumnShell (logic)")
struct SettingsThreeColumnShellTests {

    // MARK: - Section data wiring

    @Test("Shell uses SettingsSectionGroups.sections (non-admin)")
    func shellUsesNonAdminSections() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        // Verify the five §22 canonical groups are present
        let ids = Set(sections.map(\.id))
        #expect(ids.contains("account"))
        #expect(ids.contains("store"))
        #expect(ids.contains("team"))
        #expect(ids.contains("hardware"))
        #expect(ids.contains("developer"))
        #expect(!ids.contains("admin"))
    }

    @Test("Shell uses SettingsSectionGroups.sections (admin)")
    func shellUsesAdminSections() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        #expect(sections.contains { $0.id == "admin" })
    }

    // MARK: - Section → page navigation invariants

    @Test("Every section's first page has a valid settings.* ID")
    func everyFirstPageHasValidID() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        for section in sections {
            guard let firstPage = section.pages.first else {
                Issue.record("Section '\(section.id)' has no pages")
                continue
            }
            #expect(firstPage.id.hasPrefix("settings."),
                    "First page of '\(section.id)' has invalid id: \(firstPage.id)")
        }
    }

    @Test("Total navigable pages across all sections is at least 10")
    func totalNavigablePagesAtLeastTen() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        let total = sections.reduce(0) { $0 + $1.pages.count }
        #expect(total >= 10)
    }

    // MARK: - Search integration (via SettingsSearchViewModel)

    @Test("SettingsSearchViewModel starts not searching")
    @MainActor
    func vmStartsNotSearching() {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        #expect(!vm.isSearching)
        #expect(vm.results.isEmpty)
    }

    @Test("Clearing vm while searching cancels and empties results")
    @MainActor
    func clearCancelsActiveSearch() async {
        let vm = SettingsSearchViewModel(debounceInterval: 0.5) // long delay
        vm.query = "profile"
        #expect(vm.isSearching)
        vm.clear()
        #expect(!vm.isSearching)
        #expect(vm.results.isEmpty)
    }

    @Test("Search for 'roles' finds roles entry")
    @MainActor
    func searchForRoles() async {
        let vm = SettingsSearchViewModel(debounceInterval: 0)
        vm.query = "roles"
        try? await Task.sleep(for: .milliseconds(50))
        #expect(vm.results.contains { $0.id == "roles" || $0.id == "roles.matrix" })
    }

    // MARK: - Page ID resolution conventions

    /// The shell maps SettingsEntry.path → page ID by using path directly when
    /// it starts with "settings.", or prepending "settings." otherwise.
    /// These tests document and verify those path conventions in the search index.

    @Test("SettingsSearchIndex paths starting with 'settings.' are directly usable")
    func searchIndexPathsAreDirectlyUsable() {
        for entry in SettingsSearchIndex.entries {
            // All paths must start with "settings." per the index spec
            #expect(entry.path.hasPrefix("settings."),
                    "Entry '\(entry.id)' has path '\(entry.path)' not starting with 'settings.'")
        }
    }

    @Test("Each search index entry id is non-empty")
    func searchIndexEntryIDsNonEmpty() {
        for entry in SettingsSearchIndex.entries {
            #expect(!entry.id.isEmpty)
        }
    }

    // MARK: - SettingsSection / SettingsPageEntry structural

    @Test("SettingsSection Identifiable id matches stored id")
    func sectionIdentifiableID() {
        let section = SettingsSection(id: "mySection", title: "T", icon: "gear", pages: [])
        #expect(section.id == "mySection")
    }

    @Test("SettingsPageEntry Identifiable id matches stored id")
    func pageEntryIdentifiableID() {
        let page = SettingsPageEntry(id: "settings.foo", title: "Foo", icon: "star")
        #expect(page.id == "settings.foo")
    }

    @Test("SettingsSection with pages retains all pages")
    func sectionRetainsPages() {
        let pages = [
            SettingsPageEntry(id: "settings.a", title: "A", icon: "a"),
            SettingsPageEntry(id: "settings.b", title: "B", icon: "b"),
        ]
        let section = SettingsSection(id: "s", title: "S", icon: "gear", pages: pages)
        #expect(section.pages.count == 2)
        #expect(section.pages[0].id == "settings.a")
        #expect(section.pages[1].id == "settings.b")
    }

    // MARK: - Keyboard shortcuts catalogue cross-check

    @Test("Keyboard shortcut catalog references ⌘F")
    func shortcutCatalogHasCommandF() {
        let hasCmdF = SettingsShortcutDescriptor.all.contains {
            $0.key == "F" && $0.modifiers.contains("⌘")
        }
        #expect(hasCmdF)
    }

    @Test("Keyboard shortcut catalog references ⌘W")
    func shortcutCatalogHasCommandW() {
        let hasCmdW = SettingsShortcutDescriptor.all.contains {
            $0.key == "W" && $0.modifiers.contains("⌘")
        }
        #expect(hasCmdW)
    }

    @Test("Keyboard shortcut catalog references Escape with no modifiers")
    func shortcutCatalogHasEscape() {
        let hasEsc = SettingsShortcutDescriptor.all.contains {
            $0.key.lowercased().contains("esc") && $0.modifiers.isEmpty
        }
        #expect(hasEsc)
    }
}
