import SwiftUI

// MARK: - KeyboardShortcut model

/// A single entry in the centralized shortcut catalog.
///
/// `KeyEquivalent` and `EventModifiers` are both `Sendable` in SwiftUI, so the
/// struct satisfies Swift 6 strict concurrency.
public struct AppKeyboardShortcut: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let group: ShortcutGroup
    public let key: KeyEquivalent
    public let modifiers: EventModifiers
    public let description: String

    public static func == (lhs: AppKeyboardShortcut, rhs: AppKeyboardShortcut) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Human-readable display label, e.g. "⌘N".
    public var displayLabel: String {
        modifiers.displayString + key.character.displayString
    }

    /// VoiceOver announcement string.
    public var accessibilityLabel: String {
        "\(modifiers.voiceoverString)\(key.character.voiceoverName) — \(title)"
    }

    public init(
        id: String,
        title: String,
        group: ShortcutGroup,
        key: KeyEquivalent,
        modifiers: EventModifiers,
        description: String
    ) {
        self.id = id
        self.title = title
        self.group = group
        self.key = key
        self.modifiers = modifiers
        self.description = description
    }
}

// MARK: - ShortcutGroup

public enum ShortcutGroup: String, CaseIterable, Sendable {
    case file       = "File"
    case navigation = "Navigation"
    case pos        = "POS"
    case search     = "Search"
    case sync       = "Sync"
    case session    = "Session"

    public var displayTitle: String { rawValue }

    /// SF Symbol name for the group header icon.
    public var systemImage: String {
        switch self {
        case .file:       return "doc"
        case .navigation: return "sidebar.left"
        case .pos:        return "cart"
        case .search:     return "magnifyingglass"
        case .sync:       return "arrow.triangle.2.circlepath"
        case .session:    return "person.circle"
        }
    }
}

// MARK: - KeyboardShortcutCatalog

/// Centralized registry of all BizarreCRM keyboard shortcuts.
///
/// Existing `.keyboardShortcut` call-sites in POS (`PosView.swift`),
/// `RootView.swift`, and `BizarreCRMApp.swift` are left in place.
/// TODO(migration): replace each scattered `.keyboardShortcut` with
/// `.registeredKeyboardShortcut(id:onAction:)` in a follow-up PR once
/// this catalog is proven in production.
public enum KeyboardShortcutCatalog {

    // MARK: - All shortcuts

    public static let all: [AppKeyboardShortcut] = [
        // MARK: File
        .init(
            id: "new_ticket",
            title: "New Ticket",
            group: .file,
            key: .init("n"),
            modifiers: .command,
            description: "Create a new service ticket"
        ),
        .init(
            id: "new_customer",
            title: "New Customer",
            group: .file,
            key: .init("n"),
            modifiers: [.command, .shift],
            description: "Create a new customer record"
        ),
        .init(
            id: "open_search",
            title: "Open Search",
            group: .file,
            key: .init("o"),
            modifiers: .command,
            description: "Open global search"
        ),
        .init(
            id: "print_receipt",
            title: "Print Receipt",
            group: .file,
            key: .init("p"),
            modifiers: .command,
            description: "Print the current receipt"
        ),
        .init(
            id: "print_label",
            title: "Print Label",
            group: .file,
            key: .init("p"),
            modifiers: [.command, .shift],
            description: "Print a device / item label"
        ),

        // MARK: Navigation
        .init(
            id: "nav_dashboard",
            title: "Dashboard",
            group: .navigation,
            key: .init("1"),
            modifiers: .command,
            description: "Switch to Dashboard tab"
        ),
        .init(
            id: "nav_tickets",
            title: "Tickets",
            group: .navigation,
            key: .init("2"),
            modifiers: .command,
            description: "Switch to Tickets tab"
        ),
        .init(
            id: "nav_customers",
            title: "Customers",
            group: .navigation,
            key: .init("3"),
            modifiers: .command,
            description: "Switch to Customers tab"
        ),
        .init(
            id: "nav_pos",
            title: "POS",
            group: .navigation,
            key: .init("4"),
            modifiers: .command,
            description: "Switch to Point-of-Sale tab"
        ),
        .init(
            id: "nav_inventory",
            title: "Inventory",
            group: .navigation,
            key: .init("5"),
            modifiers: .command,
            description: "Navigate to Inventory"
        ),
        .init(
            id: "nav_appointments",
            title: "Appointments",
            group: .navigation,
            key: .init("6"),
            modifiers: .command,
            description: "Navigate to Appointments"
        ),

        // MARK: POS
        .init(
            id: "pos_command_palette",
            title: "Command Palette",
            group: .pos,
            key: .init("k"),
            modifiers: .command,
            description: "Open command palette"
        ),
        .init(
            id: "pos_clear_cart",
            title: "Clear Cart",
            group: .pos,
            key: .init("k"),
            modifiers: [.command, .shift],
            description: "Clear all items from the cart (confirm required)"
        ),
        .init(
            id: "pos_discount",
            title: "Add Discount",
            group: .pos,
            key: .init("d"),
            modifiers: [.command, .shift],
            description: "Apply a discount to the current line or cart"
        ),
        .init(
            id: "pos_tip",
            title: "Add Tip",
            group: .pos,
            key: .init("t"),
            modifiers: [.command, .shift],
            description: "Add or edit tip amount"
        ),
        .init(
            id: "pos_find_sku",
            title: "Find SKU / Item",
            group: .pos,
            key: .init("f"),
            modifiers: [.command, .shift],
            description: "Search inventory by SKU or name"
        ),
        .init(
            id: "pos_hold_cart",
            title: "Hold / Resume Cart",
            group: .pos,
            key: .init("h"),
            modifiers: [.command, .shift],
            description: "Park or resume a held cart"
        ),

        // MARK: Search
        .init(
            id: "search_find",
            title: "Find",
            group: .search,
            key: .init("f"),
            modifiers: .command,
            description: "Focus global search field"
        ),
        .init(
            id: "search_customer_phone",
            title: "Find Customer by Phone",
            group: .search,
            key: .init("l"),
            modifiers: [.command, .shift],
            description: "Search customers by phone number"
        ),
        .init(
            id: "search_focus",
            title: "Focus Search Bar",
            group: .search,
            key: .init("l"),
            modifiers: .command,
            description: "Move keyboard focus to the nearest search field"
        ),

        // MARK: Sync
        .init(
            id: "sync_now",
            title: "Sync Now",
            group: .sync,
            key: .init("r"),
            modifiers: .command,
            description: "Trigger an immediate data sync"
        ),

        // MARK: Session
        .init(
            id: "sign_out",
            title: "Sign Out",
            group: .session,
            key: .init("q"),
            modifiers: [.command, .shift],
            description: "Sign out of BizarreCRM"
        ),
        .init(
            id: "shortcut_overlay",
            title: "Keyboard Shortcuts",
            group: .session,
            key: .init("/"),
            modifiers: .command,
            description: "Show this keyboard shortcut cheat-sheet"
        ),
    ]

    // MARK: - Lookup helpers

    /// Returns the shortcut with the given `id`, or `nil` if not registered.
    public static func shortcut(id: String) -> AppKeyboardShortcut? {
        all.first { $0.id == id }
    }

    /// Returns all shortcuts in `group`, in catalog order.
    public static func shortcuts(in group: ShortcutGroup) -> [AppKeyboardShortcut] {
        all.filter { $0.group == group }
    }

    /// All groups that have at least one shortcut, in `ShortcutGroup.allCases` order.
    public static var populatedGroups: [ShortcutGroup] {
        ShortcutGroup.allCases.filter { group in
            all.contains { $0.group == group }
        }
    }
}

// MARK: - Display helpers (private to this module)

private extension EventModifiers {
    /// Unicode glyph string for the active modifier flags.
    var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option)  { result += "⌥" }
        if contains(.shift)   { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    /// VoiceOver-friendly prefix.
    var voiceoverString: String {
        var parts: [String] = []
        if contains(.control) { parts.append("Control") }
        if contains(.option)  { parts.append("Option") }
        if contains(.shift)   { parts.append("Shift") }
        if contains(.command) { parts.append("Command") }
        return parts.isEmpty ? "" : parts.joined(separator: "+") + "+"
    }
}

private extension Character {
    /// Glyph-safe display string for a `KeyEquivalent` character.
    var displayString: String {
        switch self {
        case "/":        return "/"
        case "\r":       return "↩"
        case "\u{1B}":   return "⎋"
        case "\u{7F}":   return "⌫"
        case "\t":       return "⇥"
        default:         return String(self).uppercased()
        }
    }

    /// VoiceOver-friendly name.
    var voiceoverName: String {
        switch self {
        case "/":        return "Slash"
        case "\r":       return "Return"
        case "\u{1B}":   return "Escape"
        case "\u{7F}":   return "Delete"
        case "\t":       return "Tab"
        default:         return String(self).uppercased()
        }
    }
}
