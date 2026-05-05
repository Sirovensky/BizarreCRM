#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - InventoryKeyboardShortcuts

/// View modifier that attaches iPad keyboard shortcuts to the inventory
/// three-column layout.  Apply with `.inventoryKeyboardShortcuts(...)`.
///
/// Shortcuts registered here:
///   ⌘N       — New item
///   ⌘F       — Focus search  (system default, documented for discoverability)
///   ⌘⇧L      — Low stock list
///   ⌘⇧R      — Receiving
///   ⌘⇧T      — Stocktake
///   ⌘⇧E      — Toggle batch-select mode
///   ⌘A       — Adjust stock for selected item
///   ⌘⌥1      — Switch to table view style
///   ⌘⌥2      — Switch to list view style
///   ⌘⌫       — Archive selected item (destructive — requires confirmation)
///
/// Ownership: §22 iPad polish (Inventory).
public struct InventoryKeyboardShortcutsModifier: ViewModifier {

    // MARK: - Bindings / closures from parent view

    let selectedItemId: Int64?
    let isBatchSelectMode: Bool
    let hasAPI: Bool

    let onNewItem: () -> Void
    let onLowStock: () -> Void
    let onReceiving: () -> Void
    let onStocktake: () -> Void
    let onToggleBatchSelect: () -> Void
    let onAdjustStock: () -> Void
    let onSwitchToTable: () -> Void
    let onSwitchToList: () -> Void
    let onArchiveSelected: () -> Void

    // MARK: - Body

    @ViewBuilder
    private func shortcut(_ label: String, key: KeyEquivalent, modifiers: EventModifiers = .command, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button("") { action() }
            .keyboardShortcut(key, modifiers: modifiers)
            .accessibilityLabel(label)
            .disabled(disabled)
            .hidden()
    }

    public func body(content: Content) -> some View {
        content
            .background(shortcut("New Item", key: "n", disabled: !hasAPI, action: onNewItem))
            .background(shortcut("Low Stock", key: "l", modifiers: [.command, .shift], disabled: !hasAPI, action: onLowStock))
            .background(shortcut("Receiving", key: "r", modifiers: [.command, .shift], disabled: !hasAPI, action: onReceiving))
            .background(shortcut("Stocktake", key: "t", modifiers: [.command, .shift], disabled: !hasAPI, action: onStocktake))
            .background(shortcut("Select Items", key: "e", modifiers: [.command, .shift], disabled: !hasAPI, action: onToggleBatchSelect))
            .background(shortcut("Adjust Stock", key: "a", disabled: selectedItemId == nil || !hasAPI, action: onAdjustStock))
            .background(shortcut("Archive Item", key: .delete, disabled: selectedItemId == nil || !hasAPI, action: onArchiveSelected))
            .background(shortcut("Table View", key: "1", modifiers: [.command, .option], action: onSwitchToTable))
            .background(shortcut("List View", key: "2", modifiers: [.command, .option], action: onSwitchToList))
    }
}

// MARK: - View extension

public extension View {
    /// Attaches `InventoryKeyboardShortcutsModifier` to any view in the
    /// inventory hierarchy (typically `InventoryThreeColumnView`).
    func inventoryKeyboardShortcuts(
        selectedItemId: Int64?,
        isBatchSelectMode: Bool,
        hasAPI: Bool,
        onNewItem: @escaping () -> Void,
        onLowStock: @escaping () -> Void,
        onReceiving: @escaping () -> Void,
        onStocktake: @escaping () -> Void,
        onToggleBatchSelect: @escaping () -> Void,
        onAdjustStock: @escaping () -> Void,
        onSwitchToTable: @escaping () -> Void,
        onSwitchToList: @escaping () -> Void,
        onArchiveSelected: @escaping () -> Void
    ) -> some View {
        modifier(InventoryKeyboardShortcutsModifier(
            selectedItemId: selectedItemId,
            isBatchSelectMode: isBatchSelectMode,
            hasAPI: hasAPI,
            onNewItem: onNewItem,
            onLowStock: onLowStock,
            onReceiving: onReceiving,
            onStocktake: onStocktake,
            onToggleBatchSelect: onToggleBatchSelect,
            onAdjustStock: onAdjustStock,
            onSwitchToTable: onSwitchToTable,
            onSwitchToList: onSwitchToList,
            onArchiveSelected: onArchiveSelected
        ))
    }
}

// MARK: - Shortcut manifest (used by tests + discoverability UI)

/// All shortcuts registered by this feature, expressed as value types
/// so tests can assert completeness without importing SwiftUI.
public struct InventoryShortcut: Sendable, Equatable {
    public let key: String
    public let modifiers: ShortcutModifiers
    public let description: String

    public struct ShortcutModifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = ShortcutModifiers(rawValue: 1 << 0)
        public static let shift   = ShortcutModifiers(rawValue: 1 << 1)
        public static let option  = ShortcutModifiers(rawValue: 1 << 2)
    }
}

public enum InventoryShortcutManifest {
    public static let all: [InventoryShortcut] = [
        .init(key: "N", modifiers: .command,              description: "New item"),
        .init(key: "L", modifiers: [.command, .shift],    description: "Low stock"),
        .init(key: "R", modifiers: [.command, .shift],    description: "Receiving"),
        .init(key: "T", modifiers: [.command, .shift],    description: "Stocktake"),
        .init(key: "E", modifiers: [.command, .shift],    description: "Toggle batch select"),
        .init(key: "A", modifiers: .command,              description: "Adjust stock"),
        .init(key: "1", modifiers: [.command, .option],   description: "Table view"),
        .init(key: "2", modifiers: [.command, .option],   description: "List view"),
        .init(key: "⌫", modifiers: .command,              description: "Archive selected item"),
    ]

    /// Keys must be unique within the feature.
    public static var hasDuplicateKeys: Bool {
        let keys = all.map { "\($0.key)-\($0.modifiers.rawValue)" }
        return Set(keys).count != keys.count
    }
}
#endif
