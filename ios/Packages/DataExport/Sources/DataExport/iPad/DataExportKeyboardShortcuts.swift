import SwiftUI

// MARK: - DataExportKeyboardShortcuts

/// Keyboard shortcut definitions for the iPad Data Export three-column view.
///
/// All shortcut metadata lives here so command-palette and `.keyboardShortcut`
/// call sites can reference a single source of truth.
public enum DataExportKeyboardShortcuts {

    // MARK: - Shortcut definitions

    public struct Shortcut: Identifiable, Sendable {
        public let id: String
        public let key: KeyEquivalent
        public let modifiers: EventModifiers
        public let displayTitle: String
        public let accessibilityHint: String

        public init(
            id: String,
            key: KeyEquivalent,
            modifiers: EventModifiers,
            displayTitle: String,
            accessibilityHint: String
        ) {
            self.id = id
            self.key = key
            self.modifiers = modifiers
            self.displayTitle = displayTitle
            self.accessibilityHint = accessibilityHint
        }
    }

    /// ⌘N — trigger a new on-demand export
    public static let newExport = Shortcut(
        id: "export.new",
        key: "n",
        modifiers: .command,
        displayTitle: "New Export",
        accessibilityHint: "Open the new export wizard"
    )

    /// ⌘D — download selected completed export
    public static let downloadSelected = Shortcut(
        id: "export.download",
        key: "d",
        modifiers: .command,
        displayTitle: "Download",
        accessibilityHint: "Download the selected export file"
    )

    /// ⌘⇧S — share selected completed export
    public static let shareSelected = Shortcut(
        id: "export.share",
        key: "s",
        modifiers: [.command, .shift],
        displayTitle: "Share…",
        accessibilityHint: "Share the selected export file"
    )

    /// ⌘R — refresh the job list
    public static let refresh = Shortcut(
        id: "export.refresh",
        key: "r",
        modifiers: .command,
        displayTitle: "Refresh",
        accessibilityHint: "Reload the export list from the server"
    )

    /// ⌘⌫ — cancel the selected export (destructive)
    public static let cancelSelected = Shortcut(
        id: "export.cancel",
        key: .delete,
        modifiers: .command,
        displayTitle: "Cancel Export",
        accessibilityHint: "Cancel the selected in-progress export"
    )

    /// ⌘1 — jump to On-Demand sidebar section
    public static let jumpOnDemand = Shortcut(
        id: "export.jump.ondemand",
        key: "1",
        modifiers: .command,
        displayTitle: "On-Demand",
        accessibilityHint: "Navigate to on-demand exports"
    )

    /// ⌘2 — jump to Scheduled sidebar section
    public static let jumpScheduled = Shortcut(
        id: "export.jump.scheduled",
        key: "2",
        modifiers: .command,
        displayTitle: "Scheduled",
        accessibilityHint: "Navigate to scheduled exports"
    )

    /// ⌘3 — jump to GDPR sidebar section
    public static let jumpGDPR = Shortcut(
        id: "export.jump.gdpr",
        key: "3",
        modifiers: .command,
        displayTitle: "GDPR",
        accessibilityHint: "Navigate to GDPR exports"
    )

    /// ⌘4 — jump to Settings sidebar section
    public static let jumpSettings = Shortcut(
        id: "export.jump.settings",
        key: "4",
        modifiers: .command,
        displayTitle: "Settings",
        accessibilityHint: "Navigate to settings exports"
    )

    /// All shortcuts as an ordered list (for help overlay / command palette).
    public static let all: [Shortcut] = [
        newExport, downloadSelected, shareSelected,
        refresh, cancelSelected,
        jumpOnDemand, jumpScheduled, jumpGDPR, jumpSettings
    ]
}

// MARK: - DataExportShortcutModifier

/// Attaches all iPad Data Export keyboard shortcuts to a view tree.
///
/// Inject once at the three-column root. The callbacks map directly to
/// `DataExportViewModel` or navigation state mutations.
public struct DataExportShortcutModifier: ViewModifier {
    let onNewExport: () -> Void
    let onDownload: () -> Void
    let onShare: () -> Void
    let onRefresh: () -> Void
    let onCancelSelected: () -> Void
    let onJumpKind: (ExportKind) -> Void

    public init(
        onNewExport: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onCancelSelected: @escaping () -> Void,
        onJumpKind: @escaping (ExportKind) -> Void
    ) {
        self.onNewExport = onNewExport
        self.onDownload = onDownload
        self.onShare = onShare
        self.onRefresh = onRefresh
        self.onCancelSelected = onCancelSelected
        self.onJumpKind = onJumpKind
    }

    public func body(content: Content) -> some View {
        content
            .keyboardShortcut(
                DataExportKeyboardShortcuts.newExport.key,
                modifiers: DataExportKeyboardShortcuts.newExport.modifiers
            )
            // Attach actions via .onKeyPress won't work here — bind directly via commands:
            // The modifier surfaces the shortcuts for discoverability in the menu bar
            // and `.commands` blocks. Actual action wiring is in the three-column view.
            .background(shortcutActions)
    }

    private var shortcutActions: some View {
        Group {
            // Navigation jump shortcuts
            Button(DataExportKeyboardShortcuts.jumpOnDemand.displayTitle) {
                onJumpKind(.onDemand)
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.jumpOnDemand.key,
                              modifiers: DataExportKeyboardShortcuts.jumpOnDemand.modifiers)
            .accessibilityHidden(true)

            Button(DataExportKeyboardShortcuts.jumpScheduled.displayTitle) {
                onJumpKind(.scheduled)
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.jumpScheduled.key,
                              modifiers: DataExportKeyboardShortcuts.jumpScheduled.modifiers)
            .accessibilityHidden(true)

            Button(DataExportKeyboardShortcuts.jumpGDPR.displayTitle) {
                onJumpKind(.gdpr)
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.jumpGDPR.key,
                              modifiers: DataExportKeyboardShortcuts.jumpGDPR.modifiers)
            .accessibilityHidden(true)

            Button(DataExportKeyboardShortcuts.jumpSettings.displayTitle) {
                onJumpKind(.settings)
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.jumpSettings.key,
                              modifiers: DataExportKeyboardShortcuts.jumpSettings.modifiers)
            .accessibilityHidden(true)

            // Export action shortcuts
            Button(DataExportKeyboardShortcuts.newExport.displayTitle) {
                onNewExport()
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.newExport.key,
                              modifiers: DataExportKeyboardShortcuts.newExport.modifiers)
            .accessibilityHidden(true)

            Button(DataExportKeyboardShortcuts.refresh.displayTitle) {
                onRefresh()
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.refresh.key,
                              modifiers: DataExportKeyboardShortcuts.refresh.modifiers)
            .accessibilityHidden(true)

            Button(DataExportKeyboardShortcuts.downloadSelected.displayTitle) {
                onDownload()
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.downloadSelected.key,
                              modifiers: DataExportKeyboardShortcuts.downloadSelected.modifiers)
            .accessibilityHidden(true)

            Button(DataExportKeyboardShortcuts.shareSelected.displayTitle) {
                onShare()
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.shareSelected.key,
                              modifiers: DataExportKeyboardShortcuts.shareSelected.modifiers)
            .accessibilityHidden(true)

            Button(DataExportKeyboardShortcuts.cancelSelected.displayTitle) {
                onCancelSelected()
            }
            .keyboardShortcut(DataExportKeyboardShortcuts.cancelSelected.key,
                              modifiers: DataExportKeyboardShortcuts.cancelSelected.modifiers)
            .accessibilityHidden(true)
        }
        .frame(width: 0, height: 0)
        .hidden()
    }
}

public extension View {
    /// Attaches all Data Export keyboard shortcuts to this view.
    func dataExportKeyboardShortcuts(
        onNewExport: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onCancelSelected: @escaping () -> Void,
        onJumpKind: @escaping (ExportKind) -> Void
    ) -> some View {
        modifier(DataExportShortcutModifier(
            onNewExport: onNewExport,
            onDownload: onDownload,
            onShare: onShare,
            onRefresh: onRefresh,
            onCancelSelected: onCancelSelected,
            onJumpKind: onJumpKind
        ))
    }
}
