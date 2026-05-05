// Core/Mac/MacKeyboardShortcuts.swift
//
// Catalog of global keyboard shortcuts for Mac Catalyst menus.
// Pure enum — no UI framework import beyond SwiftUI (for KeyEquivalent and
// EventModifiers), safe for tests and SwiftUI previews.
//
// §23 Mac (Designed for iPad) polish — keyboard shortcut catalog

import SwiftUI

/// A single keyboard shortcut definition, pairing a `KeyEquivalent` with its
/// required `EventModifiers` and a stable string identifier used for testing
/// and accessibility exposure.
public struct MacShortcut: Sendable, Equatable {
    /// Human-readable identifier — stable across app versions.
    public let id: String
    /// The primary key character.
    public let key: KeyEquivalent
    /// Required modifiers (default: `.command`).
    public let modifiers: EventModifiers
    /// Human-readable description for tooltips / accessibility.
    public let description: String

    public init(
        id: String,
        key: KeyEquivalent,
        modifiers: EventModifiers = .command,
        description: String
    ) {
        self.id = id
        self.key = key
        self.modifiers = modifiers
        self.description = description
    }
}

/// Global keyboard shortcut catalog for BizarreCRM Mac Catalyst menus.
///
/// Each constant maps directly to a `KeyboardShortcut` so SwiftUI views and
/// `CommandMenu`/`CommandGroup` definitions can share a single source of truth.
///
/// Usage:
/// ```swift
/// Button("New Ticket") { … }
///     .keyboardShortcut(MacKeyboardShortcuts.newItem)
/// ```
public enum MacKeyboardShortcuts: Sendable {

    // MARK: - Application-level

    /// ⌘Q — Quit application.
    public static let quit = MacShortcut(
        id: "mac.quit",
        key: "q",
        modifiers: .command,
        description: "Quit BizarreCRM"
    )

    /// ⌘W — Close window / dismiss sheet.
    public static let closeWindow = MacShortcut(
        id: "mac.closeWindow",
        key: "w",
        modifiers: .command,
        description: "Close Window"
    )

    // MARK: - Navigation & Creation

    /// ⌘N — New item (context-sensitive: ticket, customer, invoice …).
    public static let newItem = MacShortcut(
        id: "mac.newItem",
        key: "n",
        modifiers: .command,
        description: "New Item"
    )

    /// ⌘F — Find / search within the current view.
    public static let find = MacShortcut(
        id: "mac.find",
        key: "f",
        modifiers: .command,
        description: "Find"
    )

    /// ⌘K — Open command palette.
    public static let commandPalette = MacShortcut(
        id: "mac.commandPalette",
        key: "k",
        modifiers: .command,
        description: "Open Command Palette"
    )

    // MARK: - Data operations

    /// ⌘R — Refresh / reload current view from server.
    public static let refresh = MacShortcut(
        id: "mac.refresh",
        key: "r",
        modifiers: .command,
        description: "Refresh"
    )

    /// ⌘S — Save the current form or document.
    public static let save = MacShortcut(
        id: "mac.save",
        key: "s",
        modifiers: .command,
        description: "Save"
    )

    // MARK: - Edit history

    /// ⌘Z — Undo last action.
    public static let undo = MacShortcut(
        id: "mac.undo",
        key: "z",
        modifiers: .command,
        description: "Undo"
    )

    /// ⌘⇧Z — Redo last undone action.
    public static let redo = MacShortcut(
        id: "mac.redo",
        key: "z",
        modifiers: [.command, .shift],
        description: "Redo"
    )

    // MARK: - All shortcuts

    /// Ordered list of all cataloged shortcuts.
    /// Useful for iterating in tests and for building shortcut cheat-sheets.
    public static let all: [MacShortcut] = [
        quit,
        closeWindow,
        newItem,
        find,
        commandPalette,
        refresh,
        save,
        undo,
        redo,
    ]
}

// MARK: - SwiftUI interop

extension MacShortcut {
    /// Returns a `KeyboardShortcut` ready to pass to `.keyboardShortcut(…)`.
    public var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(key, modifiers: modifiers)
    }
}
