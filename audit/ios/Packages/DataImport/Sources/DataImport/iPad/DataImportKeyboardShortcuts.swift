import SwiftUI
import Core
import DesignSystem

// MARK: - DataImportKeyboardShortcuts

/// Keyboard shortcut definitions for the iPad import wizard.
///
/// Attach `.dataImportKeyboardShortcuts(vm:onDismiss:)` to the root wizard
/// view to activate all shortcuts.
public extension View {

    /// Registers all iPad keyboard shortcuts for the import wizard.
    ///
    /// | Shortcut            | Action                              |
    /// |---------------------|-------------------------------------|
    /// | ⌘ + Return          | Advance to the next step            |
    /// | ⌘ + [               | Go back / cancel current step       |
    /// | ⌘ + R               | Retry / reload (preview or errors)  |
    /// | ⌘ + .               | Cancel import and dismiss           |
    func dataImportKeyboardShortcuts(
        vm: ImportWizardViewModel,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(DataImportKeyboardShortcutsModifier(vm: vm, onDismiss: onDismiss))
    }
}

// MARK: - Modifier

struct DataImportKeyboardShortcutsModifier: ViewModifier {
    @Bindable var vm: ImportWizardViewModel
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            // ⌘ + Return — advance step
            .keyboardShortcut(.return, modifiers: .command)
            .overlay {
                // SwiftUI requires actual Button nodes for .keyboardShortcut to fire;
                // use zero-size hidden buttons as carriers.
                advanceButton
                retryButton
                cancelButton
            }
    }

    // MARK: - Hidden shortcut buttons

    private var advanceButton: some View {
        Button(action: advanceStep) {
            EmptyView()
        }
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Advance to next step")
        .accessibilityIdentifier("import.shortcut.advance")
        .frame(width: 0, height: 0)
        .hidden()
    }

    private var retryButton: some View {
        Button(action: retryCurrentStep) {
            EmptyView()
        }
        .keyboardShortcut("r", modifiers: .command)
        .accessibilityLabel("Retry current step")
        .accessibilityIdentifier("import.shortcut.retry")
        .frame(width: 0, height: 0)
        .hidden()
    }

    private var cancelButton: some View {
        Button(action: {
            vm.reset()
            onDismiss()
        }) {
            EmptyView()
        }
        .keyboardShortcut(".", modifiers: .command)
        .accessibilityLabel("Cancel import")
        .accessibilityIdentifier("import.shortcut.cancel")
        .frame(width: 0, height: 0)
        .hidden()
    }

    // MARK: - Actions

    @MainActor
    private func advanceStep() {
        switch vm.currentStep {
        case .chooseSource:
            vm.confirmSource()
        case .chooseEntity:
            vm.confirmEntity()
        case .mapping:
            vm.confirmMapping()
        case .start:
            Task { await vm.startImport() }
        default:
            break
        }
    }

    @MainActor
    private func retryCurrentStep() {
        switch vm.currentStep {
        case .preview:
            Task { await vm.loadPreview() }
        case .errors:
            Task { await vm.viewErrors() }
        default:
            break
        }
    }
}

// MARK: - KeyboardShortcutHelpEntry

/// Describes a single keyboard shortcut for display in a help overlay.
public struct KeyboardShortcutHelpEntry: Identifiable, Sendable {
    public var id: String { key + modifiers }
    public let key: String
    public let modifiers: String
    public let description: String

    public init(key: String, modifiers: String, description: String) {
        self.key = key
        self.modifiers = modifiers
        self.description = description
    }
}

extension DataImportKeyboardShortcutsModifier {
    /// All registered shortcuts, suitable for a help sheet.
    static var allShortcuts: [KeyboardShortcutHelpEntry] {
        [
            KeyboardShortcutHelpEntry(key: "↩", modifiers: "⌘", description: "Advance to next step"),
            KeyboardShortcutHelpEntry(key: "R",  modifiers: "⌘", description: "Retry / reload current step"),
            KeyboardShortcutHelpEntry(key: ".",  modifiers: "⌘", description: "Cancel import"),
        ]
    }
}
