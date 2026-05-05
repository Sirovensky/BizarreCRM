import Testing
@testable import Settings

// MARK: - SettingsSectionGroups Tests

@Suite("SettingsSectionGroups")
struct SettingsSectionGroupsTests {

    // MARK: - Section count

    @Test("Non-admin layout has 5 sections")
    func nonAdminHasFiveSections() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        #expect(sections.count == 5)
    }

    @Test("Admin layout has 6 sections")
    func adminHasSixSections() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        #expect(sections.count == 6)
    }

    // MARK: - Required sections present

    @Test("Non-admin sections contain Account")
    func containsAccount() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        #expect(sections.contains { $0.id == "account" })
    }

    @Test("Non-admin sections contain Store")
    func containsStore() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        #expect(sections.contains { $0.id == "store" })
    }

    @Test("Non-admin sections contain Team")
    func containsTeam() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        #expect(sections.contains { $0.id == "team" })
    }

    @Test("Non-admin sections contain Hardware")
    func containsHardware() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        #expect(sections.contains { $0.id == "hardware" })
    }

    @Test("Non-admin sections contain Developer")
    func containsDeveloper() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        #expect(sections.contains { $0.id == "developer" })
    }

    @Test("Admin layout contains Admin section")
    func adminSectionPresentWhenAdmin() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        #expect(sections.contains { $0.id == "admin" })
    }

    @Test("Non-admin layout does not contain Admin section")
    func adminSectionAbsentWhenNotAdmin() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        #expect(!sections.contains { $0.id == "admin" })
    }

    // MARK: - All sections have unique IDs

    @Test("All section IDs are unique (non-admin)")
    func sectionIDsUniqueNonAdmin() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        let ids = sections.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("All section IDs are unique (admin)")
    func sectionIDsUniqueAdmin() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        let ids = sections.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - All sections non-empty

    @Test("All sections have a title")
    func allSectionsHaveTitle() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        for section in sections {
            #expect(!section.title.isEmpty, "Section '\(section.id)' has empty title")
        }
    }

    @Test("All sections have an icon")
    func allSectionsHaveIcon() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        for section in sections {
            #expect(!section.icon.isEmpty, "Section '\(section.id)' has empty icon")
        }
    }

    @Test("All sections have at least one page")
    func allSectionsHavePages() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        for section in sections {
            #expect(!section.pages.isEmpty, "Section '\(section.id)' has no pages")
        }
    }

    // MARK: - Page entry invariants

    @Test("All page entries have unique IDs across all sections")
    func allPageIDsAreGloballyUnique() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        let allIDs = sections.flatMap { $0.pages.map(\.id) }
        #expect(Set(allIDs).count == allIDs.count)
    }

    @Test("All page entries have non-empty title")
    func allPageEntriesHaveTitle() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        for section in sections {
            for page in section.pages {
                #expect(!page.title.isEmpty, "Page '\(page.id)' in section '\(section.id)' has empty title")
            }
        }
    }

    @Test("All page entries have non-empty icon")
    func allPageEntriesHaveIcon() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        for section in sections {
            for page in section.pages {
                #expect(!page.icon.isEmpty, "Page '\(page.id)' in section '\(section.id)' has empty icon")
            }
        }
    }

    @Test("All page IDs start with 'settings.'")
    func allPageIDsStartWithSettingsPrefix() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        for section in sections {
            for page in section.pages {
                #expect(page.id.hasPrefix("settings."),
                        "Page '\(page.id)' in section '\(section.id)' should start with 'settings.'")
            }
        }
    }

    // MARK: - Specific page membership checks

    @Test("Account section contains settings.profile page")
    func accountHasProfile() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        let account = sections.first { $0.id == "account" }
        #expect(account?.pages.contains { $0.id == "settings.profile" } == true)
    }

    @Test("Store section contains settings.paymentMethods page")
    func storeHasPayments() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        let store = sections.first { $0.id == "store" }
        #expect(store?.pages.contains { $0.id == "settings.paymentMethods" } == true)
    }

    @Test("Team section contains settings.roles page")
    func teamHasRoles() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        let team = sections.first { $0.id == "team" }
        #expect(team?.pages.contains { $0.id == "settings.roles" } == true)
    }

    @Test("Hardware section contains settings.printers page")
    func hardwareHasPrinters() {
        let sections = SettingsSectionGroups.sections(includeAdmin: false)
        let hw = sections.first { $0.id == "hardware" }
        #expect(hw?.pages.contains { $0.id == "settings.printers" } == true)
    }

    @Test("Admin section contains settings.featureFlags page")
    func adminHasFeatureFlags() {
        let sections = SettingsSectionGroups.sections(includeAdmin: true)
        let admin = sections.first { $0.id == "admin" }
        #expect(admin?.pages.contains { $0.id == "settings.featureFlags" } == true)
    }

    // MARK: - Equatability

    @Test("Same sections are equal")
    func sectionEquality() {
        let a = SettingsSection(id: "foo", title: "Foo", icon: "star", pages: [])
        let b = SettingsSection(id: "foo", title: "Foo", icon: "star", pages: [])
        #expect(a == b)
    }

    @Test("Different section IDs are not equal")
    func sectionInequalityByID() {
        let a = SettingsSection(id: "foo", title: "Foo", icon: "star", pages: [])
        let b = SettingsSection(id: "bar", title: "Foo", icon: "star", pages: [])
        #expect(a != b)
    }

    @Test("SettingsPageEntry equality works")
    func pageEntryEquality() {
        let a = SettingsPageEntry(id: "settings.profile", title: "Profile", icon: "person")
        let b = SettingsPageEntry(id: "settings.profile", title: "Profile", icon: "person")
        #expect(a == b)
    }

    @Test("SettingsPageEntry inequality works")
    func pageEntryInequality() {
        let a = SettingsPageEntry(id: "settings.profile", title: "Profile", icon: "person")
        let b = SettingsPageEntry(id: "settings.preferences", title: "Preferences", icon: "slider")
        #expect(a != b)
    }
}
