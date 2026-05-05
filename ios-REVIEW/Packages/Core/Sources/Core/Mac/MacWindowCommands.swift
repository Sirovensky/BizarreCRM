// Core/Mac/MacWindowCommands.swift
//
// Builder returning CommandGroup / CommandMenu that the app-shell uses inside
// WindowGroup.commands { … }.  Each builder method is a free function or
// static factory so the app shell can compose them without inheriting any
// BizarreCRM-specific dependencies.
//
// §23 Mac (Designed for iPad) polish — window command builders

import SwiftUI

// MARK: - MacWindowCommands

/// Namespace for SwiftUI `Commands` builders used by the Mac Catalyst app shell.
///
/// Usage (in App body):
/// ```swift
/// WindowGroup { … }
///     .commands {
///         MacWindowCommands.fileCommands(onNew: { … }, onSave: { … })
///         MacWindowCommands.editCommands(onUndo: { … }, onRedo: { … })
///         MacWindowCommands.viewCommands(onRefresh: { … }, onFind: { … }, onCommandPalette: { … })
///     }
/// ```
public enum MacWindowCommands {

    // MARK: - File menu group

    /// Returns a `CommandGroup` placed after the built-in *New* item that adds
    /// BizarreCRM-specific file operations (New Item, Save).
    ///
    /// - Parameters:
    ///   - onNew: Called when the user triggers ⌘N.
    ///   - onSave: Called when the user triggers ⌘S.
    ///   - onClose: Called when the user triggers ⌘W.
    public static func fileCommands(
        onNew: @escaping @Sendable () -> Void,
        onSave: @escaping @Sendable () -> Void,
        onClose: @escaping @Sendable () -> Void = {}
    ) -> some Commands {
        CommandGroup(after: .newItem) {
            Button(MacKeyboardShortcuts.newItem.description) {
                onNew()
            }
            .keyboardShortcut(MacKeyboardShortcuts.newItem.keyboardShortcut)

            Button(MacKeyboardShortcuts.save.description) {
                onSave()
            }
            .keyboardShortcut(MacKeyboardShortcuts.save.keyboardShortcut)

            Divider()

            Button(MacKeyboardShortcuts.closeWindow.description) {
                onClose()
            }
            .keyboardShortcut(MacKeyboardShortcuts.closeWindow.keyboardShortcut)
        }
    }

    // MARK: - Edit menu group

    /// Returns a `CommandGroup` placed after the built-in *Undo/Redo* item that
    /// exposes BizarreCRM undo/redo actions through the standard Edit menu.
    ///
    /// - Parameters:
    ///   - onUndo: Called when the user triggers ⌘Z.
    ///   - onRedo: Called when the user triggers ⌘⇧Z.
    public static func editCommands(
        onUndo: @escaping @Sendable () -> Void,
        onRedo: @escaping @Sendable () -> Void
    ) -> some Commands {
        CommandGroup(after: .undoRedo) {
            Button(MacKeyboardShortcuts.undo.description) {
                onUndo()
            }
            .keyboardShortcut(MacKeyboardShortcuts.undo.keyboardShortcut)

            Button(MacKeyboardShortcuts.redo.description) {
                onRedo()
            }
            .keyboardShortcut(MacKeyboardShortcuts.redo.keyboardShortcut)
        }
    }

    // MARK: - View menu group

    /// Returns a custom `CommandMenu` called *View* that surfaces BizarreCRM
    /// navigation shortcuts (Refresh, Find, Command Palette).
    ///
    /// - Parameters:
    ///   - onRefresh: Called when the user triggers ⌘R.
    ///   - onFind: Called when the user triggers ⌘F.
    ///   - onCommandPalette: Called when the user triggers ⌘K.
    public static func viewCommands(
        onRefresh: @escaping @Sendable () -> Void,
        onFind: @escaping @Sendable () -> Void,
        onCommandPalette: @escaping @Sendable () -> Void
    ) -> some Commands {
        CommandMenu("View") {
            Button(MacKeyboardShortcuts.refresh.description) {
                onRefresh()
            }
            .keyboardShortcut(MacKeyboardShortcuts.refresh.keyboardShortcut)

            Button(MacKeyboardShortcuts.find.description) {
                onFind()
            }
            .keyboardShortcut(MacKeyboardShortcuts.find.keyboardShortcut)

            Divider()

            Button(MacKeyboardShortcuts.commandPalette.description) {
                onCommandPalette()
            }
            .keyboardShortcut(MacKeyboardShortcuts.commandPalette.keyboardShortcut)
        }
    }
}
