import Foundation

// MARK: - SettingsEntry

/// A single navigable settings entry used by `SettingsSearchIndex`.
public struct SettingsEntry: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// Dot-path used for deep-link navigation: e.g. "settings.company.tax"
    public let path: String
    /// Extra search terms that don't appear in the title.
    public let keywords: [String]
    public let iconSystemName: String
    /// Ordered breadcrumb segments, not including "Settings" itself.
    public let breadcrumb: [String]

    public init(
        id: String,
        title: String,
        path: String,
        keywords: [String],
        iconSystemName: String,
        breadcrumb: [String]
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.keywords = keywords
        self.iconSystemName = iconSystemName
        self.breadcrumb = breadcrumb
    }

    /// Full breadcrumb string for display: "Company › Tax"
    public var breadcrumbDisplay: String {
        breadcrumb.joined(separator: " › ")
    }
}

// MARK: - SettingsSearchIndex

/// Static registry of every navigable settings page / action.
/// Used by `SettingsSearchViewModel` to drive search results.
public enum SettingsSearchIndex {

    // MARK: All entries

    public static let entries: [SettingsEntry] = [
        // MARK: Profile
        .init(id: "profile",
              title: "Profile",
              path: "settings.profile",
              keywords: ["name", "avatar", "photo", "password", "email", "phone", "job title", "display name"],
              iconSystemName: "person.circle",
              breadcrumb: ["Profile"]),

        .init(id: "profile.changePassword",
              title: "Change Password",
              path: "settings.profile.changePassword",
              keywords: ["password", "security", "credentials", "reset"],
              iconSystemName: "lock.rotation",
              breadcrumb: ["Profile", "Change Password"]),

        .init(id: "preferences",
              title: "Preferences",
              path: "settings.preferences",
              keywords: ["theme", "dark mode", "light mode", "compact", "default view", "tickets", "sort", "filter",
                         "notification sound", "desktop notifications", "language", "timezone", "sidebar",
                         "user preferences", "per-user", "page size"],
              iconSystemName: "slider.horizontal.3",
              breadcrumb: ["Preferences"]),

        // MARK: Company / Organization
        .init(id: "businessProfile",
              title: "Business Profile",
              path: "settings.businessProfile",
              keywords: ["store name", "store", "shop name", "address", "phone", "email", "timezone",
                         "currency", "receipt header", "receipt footer", "business identity", "store config"],
              iconSystemName: "building",
              breadcrumb: ["Business Profile"]),

        .init(id: "company",
              title: "Company Info",
              path: "settings.company",
              keywords: ["organization", "business", "name", "address", "logo", "branding", "shop"],
              iconSystemName: "building.2",
              breadcrumb: ["Company"]),

        .init(id: "company.tax",
              title: "Tax Settings",
              path: "settings.company.tax",
              keywords: ["vat", "gst", "sales tax", "tax rate", "tax number", "exempt"],
              iconSystemName: "percent",
              breadcrumb: ["Company", "Tax"]),

        .init(id: "company.hours",
              title: "Business Hours",
              path: "settings.company.hours",
              keywords: ["open", "close", "schedule", "weekday", "weekend", "business hours", "store hours"],
              iconSystemName: "clock",
              breadcrumb: ["Company", "Hours"]),

        .init(id: "company.holidays",
              title: "Holiday Calendar",
              path: "settings.company.holidays",
              keywords: ["holiday", "closure", "closed", "public holiday", "day off", "vacation"],
              iconSystemName: "calendar.badge.exclamationmark",
              breadcrumb: ["Company", "Holidays"]),

        // MARK: Locations
        .init(id: "locations",
              title: "Locations",
              path: "settings.locations",
              keywords: ["store", "branch", "outlet", "multi-location", "address", "site"],
              iconSystemName: "mappin.and.ellipse",
              breadcrumb: ["Locations"]),

        .init(id: "locations.add",
              title: "Add Location",
              path: "settings.locations.add",
              keywords: ["new location", "store", "branch", "outlet"],
              iconSystemName: "mappin.circle.fill",
              breadcrumb: ["Locations", "Add Location"]),

        // MARK: Payments
        .init(id: "payments",
              title: "Payment Methods",
              path: "settings.payments",
              keywords: ["card", "cash", "stripe", "blockchyp", "terminal", "reader", "credit", "debit", "tap to pay"],
              iconSystemName: "creditcard",
              breadcrumb: ["Payments"]),

        .init(id: "payments.blockchyp",
              title: "BlockChyp Terminal",
              path: "settings.payments.blockchyp",
              keywords: ["hardware", "terminal", "card reader", "blockchyp", "pairing", "payment device"],
              iconSystemName: "wave.3.right",
              breadcrumb: ["Payments", "BlockChyp"]),

        .init(id: "payments.priceOverrides",
              title: "Price Overrides",
              path: "settings.payments.priceOverrides",
              keywords: ["discount", "override", "price change", "authorization", "manager approval"],
              iconSystemName: "tag",
              breadcrumb: ["Payments", "Price Overrides"]),

        // MARK: Notifications
        .init(id: "notifications",
              title: "Notifications",
              path: "settings.notifications",
              keywords: ["push", "alerts", "email", "sms", "remind", "badge", "sound"],
              iconSystemName: "bell",
              breadcrumb: ["Notifications"]),

        .init(id: "notifications.channels",
              title: "Notification Channels",
              path: "settings.notifications.channels",
              keywords: ["channel", "category", "ticket", "appointment", "invoice", "push"],
              iconSystemName: "bell.badge",
              breadcrumb: ["Notifications", "Channels"]),

        // MARK: Hardware
        .init(id: "hardware.printers",
              title: "Printers",
              path: "settings.hardware.printers",
              keywords: ["receipt", "print", "bluetooth", "wifi", "label", "star", "epson"],
              iconSystemName: "printer",
              breadcrumb: ["Hardware", "Printers"]),

        .init(id: "hardware.cashDrawer",
              title: "Cash Drawer",
              path: "settings.hardware.cashDrawer",
              keywords: ["drawer", "cash box", "till", "open drawer"],
              iconSystemName: "archivebox",
              breadcrumb: ["Hardware", "Cash Drawer"]),

        // MARK: Communications / SMS
        .init(id: "smsProvider",
              title: "SMS Provider",
              path: "settings.smsProvider",
              keywords: ["twilio", "sms", "text", "messaging", "phone number", "sender", "message provider"],
              iconSystemName: "message",
              breadcrumb: ["SMS Provider"]),

        // MARK: Appearance
        .init(id: "appearance",
              title: "Appearance",
              path: "settings.appearance",
              keywords: ["theme", "dark mode", "light mode", "color", "font", "display"],
              iconSystemName: "paintbrush",
              breadcrumb: ["Appearance"]),

        .init(id: "appearance.language",
              title: "Language & Region",
              path: "settings.appearance.language",
              keywords: ["language", "locale", "region", "currency", "date format", "time format", "i18n", "localization"],
              iconSystemName: "globe",
              breadcrumb: ["Appearance", "Language"]),

        // MARK: Security & Danger Zone
        .init(id: "security",
              title: "Security",
              path: "settings.security",
              keywords: ["biometric", "faceid", "touchid", "pin", "2fa", "two factor", "session"],
              iconSystemName: "lock.shield",
              breadcrumb: ["Security"]),

        .init(id: "security.dangerZone",
              title: "Danger Zone",
              path: "settings.security.dangerZone",
              keywords: ["delete", "wipe", "reset", "danger", "purge", "account deletion", "factory reset"],
              iconSystemName: "exclamationmark.triangle.fill",
              breadcrumb: ["Security", "Danger Zone"]),

        // MARK: Staff / Roles
        .init(id: "roles",
              title: "Roles & Permissions",
              path: "settings.roles",
              keywords: ["role", "permission", "access", "admin", "owner", "technician", "staff", "employee", "capability"],
              iconSystemName: "person.2.badge.key",
              breadcrumb: ["Roles"]),

        .init(id: "roles.matrix",
              title: "Permission Matrix",
              path: "settings.roles.matrix",
              keywords: ["permission", "matrix", "allow", "deny", "capability", "access control"],
              iconSystemName: "tablecells",
              breadcrumb: ["Roles", "Permission Matrix"]),

        // MARK: Audit
        .init(id: "auditLogs",
              title: "Audit Logs",
              path: "settings.auditLogs",
              keywords: ["audit", "log", "history", "activity", "trail", "compliance", "changes"],
              iconSystemName: "list.bullet.clipboard",
              breadcrumb: ["Audit Logs"]),

        // MARK: Data Import / Export
        .init(id: "dataImport",
              title: "Data Import",
              path: "settings.dataImport",
              keywords: ["import", "csv", "upload", "migrate", "bulk"],
              iconSystemName: "square.and.arrow.down",
              breadcrumb: ["Data Import"]),

        .init(id: "dataExport",
              title: "Data Export",
              path: "settings.dataExport",
              keywords: ["export", "csv", "download", "backup", "report"],
              iconSystemName: "square.and.arrow.up",
              breadcrumb: ["Data Export"]),

        // MARK: Kiosk / Training
        .init(id: "kioskMode",
              title: "Kiosk Mode",
              path: "settings.kioskMode",
              keywords: ["kiosk", "self service", "checkout", "standalone", "customer facing"],
              iconSystemName: "desktopcomputer",
              breadcrumb: ["Kiosk Mode"]),

        .init(id: "trainingMode",
              title: "Training Mode",
              path: "settings.trainingMode",
              keywords: ["training", "demo", "sandbox", "practice", "test", "simulation"],
              iconSystemName: "graduationcap",
              breadcrumb: ["Training Mode"]),

        .init(id: "setupWizard",
              title: "Setup Wizard",
              path: "settings.setupWizard",
              keywords: ["setup", "wizard", "onboarding", "configure", "getting started", "initial"],
              iconSystemName: "wand.and.sparkles",
              breadcrumb: ["Setup Wizard"]),

        // MARK: Device Templates
        .init(id: "deviceTemplates",
              title: "Device Templates",
              path: "settings.deviceTemplates",
              keywords: ["template", "device", "preset", "configuration", "profile"],
              iconSystemName: "ipad",
              breadcrumb: ["Device Templates"]),

        // MARK: Marketing
        .init(id: "marketing",
              title: "Marketing",
              path: "settings.marketing",
              keywords: ["campaign", "email", "sms", "promotion", "blast", "newsletter"],
              iconSystemName: "megaphone",
              breadcrumb: ["Marketing"]),

        .init(id: "marketing.loyalty",
              title: "Loyalty Plans",
              path: "settings.marketing.loyalty",
              keywords: ["loyalty", "points", "rewards", "tier", "earn", "redeem"],
              iconSystemName: "star.circle",
              breadcrumb: ["Marketing", "Loyalty Plans"]),

        .init(id: "marketing.reviews",
              title: "Review Platforms",
              path: "settings.marketing.reviews",
              keywords: ["google", "yelp", "review", "rating", "feedback", "reputation"],
              iconSystemName: "star.bubble",
              breadcrumb: ["Marketing", "Reviews"]),

        .init(id: "marketing.referral",
              title: "Referral Rules",
              path: "settings.marketing.referral",
              keywords: ["referral", "refer a friend", "reward", "credit", "bonus"],
              iconSystemName: "person.crop.circle.badge.plus",
              breadcrumb: ["Marketing", "Referral Rules"]),

        .init(id: "marketing.survey",
              title: "Survey Settings",
              path: "settings.marketing.survey",
              keywords: ["survey", "csat", "nps", "satisfaction", "feedback form"],
              iconSystemName: "questionmark.bubble",
              breadcrumb: ["Marketing", "Survey"]),

        // MARK: Integrations
        .init(id: "integrations.widgets",
              title: "Widgets",
              path: "settings.integrations.widgets",
              keywords: ["widget", "home screen", "lock screen", "standby", "shortcut"],
              iconSystemName: "square.grid.2x2",
              breadcrumb: ["Integrations", "Widgets"]),

        .init(id: "integrations.shortcuts",
              title: "Shortcuts",
              path: "settings.integrations.shortcuts",
              keywords: ["siri", "shortcut", "intent", "automation", "command"],
              iconSystemName: "link",
              breadcrumb: ["Integrations", "Shortcuts"]),

        // MARK: Admin
        .init(id: "admin.tenant",
              title: "Tenant Admin",
              path: "settings.admin.tenant",
              keywords: ["admin", "tenant", "plan", "subscription", "api", "usage", "impersonate"],
              iconSystemName: "building.columns",
              breadcrumb: ["Admin", "Tenant"]),

        .init(id: "admin.featureFlags",
              title: "Feature Flags",
              path: "settings.admin.featureFlags",
              keywords: ["flag", "feature", "toggle", "override", "experiment", "beta"],
              iconSystemName: "flag",
              breadcrumb: ["Admin", "Feature Flags"]),

        // MARK: About / Diagnostics
        .init(id: "about",
              title: "About",
              path: "settings.about",
              keywords: ["version", "build", "release", "licenses", "open source"],
              iconSystemName: "info.circle",
              breadcrumb: ["About"]),

        .init(id: "diagnostics",
              title: "Sync Diagnostics",
              path: "settings.diagnostics",
              keywords: ["sync", "debug", "diagnostic", "connection", "queue", "offline"],
              iconSystemName: "antenna.radiowaves.left.and.right",
              breadcrumb: ["Diagnostics"]),
    ]

    // MARK: Filter

    /// Returns entries matching `query` using prefix / contains / word-boundary fuzzy logic.
    /// Empty query returns all entries.
    public static func filter(query: String) -> [SettingsEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }

        return entries.filter { entry in
            matches(entry: entry, query: q)
        }
    }

    // MARK: Private helpers

    private static func matches(entry: SettingsEntry, query: String) -> Bool {
        let title = entry.title.lowercased()
        let path  = entry.path.lowercased()
        let crumb = entry.breadcrumb.joined(separator: " ").lowercased()

        // Exact prefix on title wins first
        if title.hasPrefix(query) { return true }
        // Title contains query
        if title.contains(query) { return true }
        // Breadcrumb contains query
        if crumb.contains(query) { return true }
        // Path contains query
        if path.contains(query) { return true }

        // Any keyword prefix/contains match
        for keyword in entry.keywords {
            let kw = keyword.lowercased()
            if kw.hasPrefix(query) || kw.contains(query) { return true }
        }

        // Word-boundary fuzzy: each space-separated token in query must appear in title or any keyword
        let tokens = query.split(separator: " ").map(String.init)
        if tokens.count > 1 {
            let allText = ([title, crumb] + entry.keywords.map { $0.lowercased() }).joined(separator: " ")
            return tokens.allSatisfy { allText.contains($0) }
        }

        return false
    }
}
