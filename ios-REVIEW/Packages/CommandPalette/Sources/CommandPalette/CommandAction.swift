import Foundation

// MARK: - CommandPaletteContext

/// Describes what the user is currently looking at when opening the palette.
public enum CommandPaletteContext: Sendable, Equatable {
    case none
    case ticket(id: String)
    case customer(id: String)
}

// MARK: - EntitySuggestion

/// A parsed entity that the palette detected from free-text input.
public enum EntitySuggestion: Sendable, Equatable {
    case ticket(id: String)
    case phone(number: String)
    case sku(value: String)
}

// MARK: - KeyboardShortcutHint

/// Human-readable description of a keyboard shortcut shown in result rows.
///
/// Examples: `⌘N`, `⌘⇧F`, `⌘,`
/// Set `modifiers` from most to least significant: ⌘ → ⌃ → ⌥ → ⇧.
public struct KeyboardShortcutHint: Sendable, Equatable {
    /// Modifier glyphs in display order (e.g. ["⌘", "⇧"]).
    public let modifiers: [String]
    /// The base key glyph (e.g. "N", "F", ",").
    public let key: String

    /// Compact display string, e.g. "⌘⇧F".
    public var displayString: String {
        modifiers.joined() + key
    }

    public init(modifiers: [String] = [], key: String) {
        self.modifiers = modifiers
        self.key = key
    }
}

// MARK: - CommandAction

/// A single action the user can execute from the Command Palette.
///
/// Handlers are caller-supplied closures so this package has no
/// dependency on routing, navigation, or business logic.
public struct CommandAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// SF Symbol name.
    public let icon: String
    /// Additional terms used for fuzzy matching (not displayed).
    public let keywords: [String]
    /// Optional keyboard shortcut hint displayed in the result row.
    /// Purely decorative — the actual shortcut registration is the host app's
    /// responsibility via `.keyboardShortcut(_:modifiers:)` on a Menu command.
    public let shortcutHint: KeyboardShortcutHint?
    /// Executed when the user selects this action.
    public let handler: @Sendable () -> Void

    public init(
        id: String,
        title: String,
        icon: String,
        keywords: [String] = [],
        shortcutHint: KeyboardShortcutHint? = nil,
        handler: @escaping @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.keywords = keywords
        self.shortcutHint = shortcutHint
        self.handler = handler
    }
}

// MARK: - Static catalog

/// The 15 built-in actions. Handlers are populated by the host app at the
/// call site — the catalog just declares id/title/icon/keywords.
public enum CommandCatalog {
    /// Returns stub actions with no-op handlers. Replace handlers at the call site.
    public static func defaultActions(
        newTicket:          @escaping @Sendable () -> Void = {},
        newCustomer:        @escaping @Sendable () -> Void = {},
        findCustomerPhone:  @escaping @Sendable () -> Void = {},
        findCustomerName:   @escaping @Sendable () -> Void = {},
        openDashboard:      @escaping @Sendable () -> Void = {},
        openPOS:            @escaping @Sendable () -> Void = {},
        clockIn:            @escaping @Sendable () -> Void = {},
        clockOut:           @escaping @Sendable () -> Void = {},
        openTickets:        @escaping @Sendable () -> Void = {},
        openInventory:      @escaping @Sendable () -> Void = {},
        settingsTax:        @escaping @Sendable () -> Void = {},
        settingsHours:      @escaping @Sendable () -> Void = {},
        reportsRevenue:     @escaping @Sendable () -> Void = {},
        sendSMS:            @escaping @Sendable () -> Void = {},
        signOut:            @escaping @Sendable () -> Void = {}
    ) -> [CommandAction] {
        [
            CommandAction(
                id: "new-ticket",
                title: "New Ticket",
                icon: "ticket",
                keywords: ["create", "repair", "job", "add"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘"], key: "N"),
                handler: newTicket
            ),
            CommandAction(
                id: "new-customer",
                title: "New Customer",
                icon: "person.badge.plus",
                keywords: ["create", "add", "client", "contact"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘", "⇧"], key: "N"),
                handler: newCustomer
            ),
            CommandAction(
                id: "find-customer-phone",
                title: "Find Customer by Phone",
                icon: "phone.fill",
                keywords: ["search", "lookup", "mobile", "number"],
                handler: findCustomerPhone
            ),
            CommandAction(
                id: "find-customer-name",
                title: "Find Customer by Name",
                icon: "person.fill.viewfinder",
                keywords: ["search", "lookup", "client"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘"], key: "F"),
                handler: findCustomerName
            ),
            CommandAction(
                id: "open-dashboard",
                title: "Open Dashboard",
                icon: "gauge",
                keywords: ["home", "overview", "main", "hub"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘"], key: "1"),
                handler: openDashboard
            ),
            CommandAction(
                id: "open-pos",
                title: "Open POS",
                icon: "cart.fill",
                keywords: ["sale", "register", "checkout", "payment"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘"], key: "2"),
                handler: openPOS
            ),
            CommandAction(
                id: "clock-in",
                title: "Clock In",
                icon: "clock.badge.checkmark",
                keywords: ["timeclock", "start", "shift", "punch"],
                handler: clockIn
            ),
            CommandAction(
                id: "clock-out",
                title: "Clock Out",
                icon: "clock.badge.xmark",
                keywords: ["timeclock", "end", "shift", "punch"],
                handler: clockOut
            ),
            CommandAction(
                id: "open-tickets",
                title: "Open Tickets",
                icon: "list.bullet.clipboard",
                keywords: ["repair", "jobs", "queue", "work"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘"], key: "3"),
                handler: openTickets
            ),
            CommandAction(
                id: "open-inventory",
                title: "Open Inventory",
                icon: "shippingbox.fill",
                keywords: ["parts", "stock", "items", "catalog"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘"], key: "4"),
                handler: openInventory
            ),
            CommandAction(
                id: "settings-tax",
                title: "Settings: Tax",
                icon: "percent",
                keywords: ["tax", "vat", "config", "preferences", "rate"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘"], key: ","),
                handler: settingsTax
            ),
            CommandAction(
                id: "settings-hours",
                title: "Settings: Hours",
                icon: "clock.fill",
                keywords: ["business hours", "schedule", "open", "config"],
                handler: settingsHours
            ),
            CommandAction(
                id: "reports-revenue",
                title: "Reports: Revenue This Month",
                icon: "chart.bar.fill",
                keywords: ["revenue", "sales", "income", "analytics", "monthly"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘", "⇧"], key: "R"),
                handler: reportsRevenue
            ),
            CommandAction(
                id: "send-sms",
                title: "Send SMS",
                icon: "message.fill",
                keywords: ["text", "message", "customer", "notify"],
                shortcutHint: KeyboardShortcutHint(modifiers: ["⌘", "⇧"], key: "M"),
                handler: sendSMS
            ),
            CommandAction(
                id: "sign-out",
                title: "Sign Out",
                icon: "rectangle.portrait.and.arrow.right",
                keywords: ["logout", "quit", "session"],
                handler: signOut
            )
        ]
    }
}
