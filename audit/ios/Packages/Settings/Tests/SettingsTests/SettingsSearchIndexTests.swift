import Testing
@testable import Settings

// MARK: - SettingsSearchIndex Tests

@Suite("SettingsSearchIndex.filter(query:)")
struct SettingsSearchIndexTests {

    // MARK: - Empty / all

    @Test("Empty query returns all entries")
    func emptyQueryReturnsAll() {
        let results = SettingsSearchIndex.filter(query: "")
        #expect(results.count == SettingsSearchIndex.entries.count)
    }

    @Test("Whitespace-only query returns all entries")
    func whitespaceQueryReturnsAll() {
        let results = SettingsSearchIndex.filter(query: "   ")
        #expect(results.count == SettingsSearchIndex.entries.count)
    }

    @Test("All entries have unique IDs")
    func allEntriesHaveUniqueIDs() {
        let ids = SettingsSearchIndex.entries.map(\.id)
        let unique = Set(ids)
        #expect(ids.count == unique.count)
    }

    @Test("All entries have non-empty title")
    func allEntriesHaveNonEmptyTitle() {
        for entry in SettingsSearchIndex.entries {
            #expect(!entry.title.isEmpty, "Entry \(entry.id) has empty title")
        }
    }

    @Test("All entries have at least one breadcrumb segment")
    func allEntriesHaveBreadcrumb() {
        for entry in SettingsSearchIndex.entries {
            #expect(!entry.breadcrumb.isEmpty, "Entry \(entry.id) has empty breadcrumb")
        }
    }

    // MARK: - Title matching

    @Test("Exact title match — 'Profile'")
    func exactTitleMatchProfile() {
        let results = SettingsSearchIndex.filter(query: "Profile")
        #expect(results.contains { $0.id == "profile" })
    }

    @Test("Case-insensitive title match — 'profile'")
    func caseInsensitiveProfile() {
        let results = SettingsSearchIndex.filter(query: "profile")
        #expect(results.contains { $0.id == "profile" })
    }

    @Test("Partial title match — 'Tax'")
    func partialTitleTax() {
        let results = SettingsSearchIndex.filter(query: "Tax")
        #expect(results.contains { $0.id == "company.tax" })
    }

    @Test("Title substring match — 'hours'")
    func titleSubstringHours() {
        let results = SettingsSearchIndex.filter(query: "hours")
        #expect(results.contains { $0.id == "company.hours" })
    }

    @Test("Title substring match — 'holiday'")
    func titleSubstringHoliday() {
        let results = SettingsSearchIndex.filter(query: "holiday")
        #expect(results.contains { $0.id == "company.holidays" })
    }

    @Test("Title match — 'Appearance'")
    func titleAppearance() {
        let results = SettingsSearchIndex.filter(query: "Appearance")
        #expect(results.contains { $0.id == "appearance" })
    }

    @Test("Title match — 'Audit'")
    func titleAudit() {
        let results = SettingsSearchIndex.filter(query: "Audit")
        #expect(results.contains { $0.id == "auditLogs" })
    }

    // MARK: - Keyword matching

    @Test("Keyword match — 'vat' finds Tax Settings")
    func keywordVATfindsTax() {
        let results = SettingsSearchIndex.filter(query: "vat")
        #expect(results.contains { $0.id == "company.tax" })
    }

    @Test("Keyword match — 'gst' finds Tax Settings")
    func keywordGSTfindsTax() {
        let results = SettingsSearchIndex.filter(query: "gst")
        #expect(results.contains { $0.id == "company.tax" })
    }

    @Test("Keyword match — 'sales tax' finds Tax Settings")
    func keywordSalesTaxfindsTax() {
        let results = SettingsSearchIndex.filter(query: "sales tax")
        #expect(results.contains { $0.id == "company.tax" })
    }

    @Test("Keyword match — 'twilio' finds SMS Provider")
    func keywordTwilioFindsSMS() {
        let results = SettingsSearchIndex.filter(query: "twilio")
        #expect(results.contains { $0.id == "smsProvider" })
    }

    @Test("Keyword match — 'blockchyp' finds BlockChyp entry")
    func keywordBlockChyp() {
        let results = SettingsSearchIndex.filter(query: "blockchyp")
        #expect(results.contains { $0.id == "payments.blockchyp" })
    }

    @Test("Keyword match — 'receipt' finds Printers")
    func keywordReceiptFindsPrinters() {
        let results = SettingsSearchIndex.filter(query: "receipt")
        #expect(results.contains { $0.id == "hardware.printers" })
    }

    @Test("Keyword match — 'csv' finds Data Import or Export")
    func keywordCSV() {
        let results = SettingsSearchIndex.filter(query: "csv")
        #expect(results.contains { $0.id == "dataImport" || $0.id == "dataExport" })
    }

    @Test("Keyword match — 'kiosk' finds Kiosk Mode")
    func keywordKiosk() {
        let results = SettingsSearchIndex.filter(query: "kiosk")
        #expect(results.contains { $0.id == "kioskMode" })
    }

    @Test("Keyword match — 'nps' finds Survey Settings")
    func keywordNPSfindsSurvey() {
        let results = SettingsSearchIndex.filter(query: "nps")
        #expect(results.contains { $0.id == "marketing.survey" })
    }

    @Test("Keyword match — 'google' finds Review Platforms")
    func keywordGoogleFindsReviews() {
        let results = SettingsSearchIndex.filter(query: "google")
        #expect(results.contains { $0.id == "marketing.reviews" })
    }

    @Test("Keyword match — 'loyalty' finds Loyalty Plans")
    func keywordLoyalty() {
        let results = SettingsSearchIndex.filter(query: "loyalty")
        #expect(results.contains { $0.id == "marketing.loyalty" })
    }

    @Test("Keyword match — 'referral' finds Referral Rules")
    func keywordReferral() {
        let results = SettingsSearchIndex.filter(query: "referral")
        #expect(results.contains { $0.id == "marketing.referral" })
    }

    @Test("Keyword match — 'dark mode' finds Appearance")
    func keywordDarkMode() {
        let results = SettingsSearchIndex.filter(query: "dark mode")
        #expect(results.contains { $0.id == "appearance" })
    }

    @Test("Keyword match — 'faceid' finds Security")
    func keywordFaceID() {
        let results = SettingsSearchIndex.filter(query: "faceid")
        #expect(results.contains { $0.id == "security" })
    }

    @Test("Keyword match — 'permission' finds Roles")
    func keywordPermission() {
        let results = SettingsSearchIndex.filter(query: "permission")
        #expect(results.contains { $0.id == "roles" || $0.id == "roles.matrix" })
    }

    @Test("Keyword match — 'danger' finds Danger Zone")
    func keywordDanger() {
        let results = SettingsSearchIndex.filter(query: "danger")
        #expect(results.contains { $0.id == "security.dangerZone" })
    }

    @Test("Keyword match — 'widget' finds Widgets")
    func keywordWidget() {
        let results = SettingsSearchIndex.filter(query: "widget")
        #expect(results.contains { $0.id == "integrations.widgets" })
    }

    @Test("Keyword match — 'siri' finds Shortcuts")
    func keywordSiri() {
        let results = SettingsSearchIndex.filter(query: "siri")
        #expect(results.contains { $0.id == "integrations.shortcuts" })
    }

    @Test("Keyword match — 'flag' finds Feature Flags")
    func keywordFlag() {
        let results = SettingsSearchIndex.filter(query: "flag")
        #expect(results.contains { $0.id == "admin.featureFlags" })
    }

    @Test("Keyword match — 'impersonate' finds Tenant Admin")
    func keywordImpersonate() {
        let results = SettingsSearchIndex.filter(query: "impersonate")
        #expect(results.contains { $0.id == "admin.tenant" })
    }

    @Test("Keyword match — 'onboarding' finds Setup Wizard")
    func keywordOnboarding() {
        let results = SettingsSearchIndex.filter(query: "onboarding")
        #expect(results.contains { $0.id == "setupWizard" })
    }

    @Test("Keyword match — 'language' finds Language & Region")
    func keywordLanguage() {
        let results = SettingsSearchIndex.filter(query: "language")
        #expect(results.contains { $0.id == "appearance.language" })
    }

    // MARK: - No-match cases

    @Test("Nonsense query returns empty results")
    func nonsenseQueryEmpty() {
        let results = SettingsSearchIndex.filter(query: "xyzzy_notaword")
        #expect(results.isEmpty)
    }

    @Test("Gibberish returns empty results")
    func gibberishEmpty() {
        let results = SettingsSearchIndex.filter(query: "qwerty_not_real_1234")
        #expect(results.isEmpty)
    }

    // MARK: - Multi-token fuzzy

    @Test("Multi-word query 'business hours' finds Hours entry")
    func multiWordBusinessHours() {
        let results = SettingsSearchIndex.filter(query: "business hours")
        #expect(results.contains { $0.id == "company.hours" })
    }

    @Test("Multi-word query 'data import' finds Data Import")
    func multiWordDataImport() {
        let results = SettingsSearchIndex.filter(query: "data import")
        #expect(results.contains { $0.id == "dataImport" })
    }

    // MARK: - Breadcrumb matching

    @Test("Breadcrumb match — 'company' finds company sub-pages")
    func breadcrumbCompany() {
        let results = SettingsSearchIndex.filter(query: "company")
        let ids = Set(results.map(\.id))
        #expect(ids.contains("company"))
    }

    @Test("breadcrumbDisplay returns segments joined by ›")
    func breadcrumbDisplay() {
        let entry = SettingsSearchIndex.entries.first { $0.id == "company.tax" }
        #expect(entry?.breadcrumbDisplay == "Company › Tax")
    }

    // MARK: - Total count sanity

    @Test("Index has at least 30 entries")
    func atLeast30Entries() {
        #expect(SettingsSearchIndex.entries.count >= 30)
    }
}
