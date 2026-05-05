import Testing
@testable import Settings

// MARK: - SettingsShortcutDescriptor Tests

@Suite("SettingsShortcutDescriptor")
struct SettingsKeyboardShortcutsTests {

    // MARK: - Descriptor catalog

    @Test("Shortcut catalog has at least 4 entries")
    func catalogHasEnoughEntries() {
        #expect(SettingsShortcutDescriptor.all.count >= 4)
    }

    @Test("All shortcut descriptors have unique IDs")
    func allDescriptorsHaveUniqueIDs() {
        let ids = SettingsShortcutDescriptor.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("All shortcut descriptors have non-empty title")
    func allDescriptorsHaveTitle() {
        for desc in SettingsShortcutDescriptor.all {
            #expect(!desc.title.isEmpty, "Descriptor '\(desc.id)' has empty title")
        }
    }

    @Test("All shortcut descriptors have non-empty key")
    func allDescriptorsHaveKey() {
        for desc in SettingsShortcutDescriptor.all {
            #expect(!desc.key.isEmpty, "Descriptor '\(desc.id)' has empty key")
        }
    }

    // MARK: - Specific shortcuts

    @Test("'search' shortcut exists")
    func searchShortcutExists() {
        #expect(SettingsShortcutDescriptor.all.contains { $0.id == "search" })
    }

    @Test("'close' shortcut exists")
    func closeShortcutExists() {
        #expect(SettingsShortcutDescriptor.all.contains { $0.id == "close" })
    }

    @Test("'open' shortcut exists with ⌘ modifier")
    func openShortcutHasCommandModifier() {
        let open = SettingsShortcutDescriptor.all.first { $0.id == "open" }
        #expect(open?.modifiers.contains("⌘") == true)
    }

    @Test("'search' shortcut key is 'F'")
    func searchShortcutKeyIsF() {
        let search = SettingsShortcutDescriptor.all.first { $0.id == "search" }
        #expect(search?.key == "F")
    }

    @Test("'close' shortcut key is 'W'")
    func closeShortcutKeyIsW() {
        let close = SettingsShortcutDescriptor.all.first { $0.id == "close" }
        #expect(close?.key == "W")
    }

    @Test("'dismissSearch' shortcut has empty modifier string")
    func dismissSearchHasNoModifiers() {
        let dismiss = SettingsShortcutDescriptor.all.first { $0.id == "dismissSearch" }
        #expect(dismiss?.modifiers == "")
    }

    // MARK: - Init / value types

    @Test("SettingsShortcutDescriptor stores all properties correctly")
    func descriptorStoresProperties() {
        let desc = SettingsShortcutDescriptor(
            id: "test",
            title: "Test Action",
            key: "T",
            modifiers: "⌘⇧"
        )
        #expect(desc.id == "test")
        #expect(desc.title == "Test Action")
        #expect(desc.key == "T")
        #expect(desc.modifiers == "⌘⇧")
    }

    @Test("SettingsShortcutDescriptor conforms to Identifiable using id field")
    func descriptorIsIdentifiable() {
        let desc = SettingsShortcutDescriptor(id: "uniqueID", title: "T", key: "K", modifiers: "")
        // Identifiable conformance: id property must equal the stored id
        #expect(desc.id == "uniqueID")
    }

    // MARK: - Modifier string format

    @Test("searchAlt shortcut contains both ⌘ and ⇧ in modifiers")
    func searchAltHasCommandAndShift() {
        let alt = SettingsShortcutDescriptor.all.first { $0.id == "searchAlt" }
        #expect(alt?.modifiers.contains("⌘") == true)
        #expect(alt?.modifiers.contains("⇧") == true)
    }

    // MARK: - Sendable

    @Test("SettingsShortcutDescriptor is usable from async context")
    func descriptorIsUsableAsyncly() async {
        let all = await Task.detached {
            SettingsShortcutDescriptor.all
        }.value
        #expect(!all.isEmpty)
    }
}
