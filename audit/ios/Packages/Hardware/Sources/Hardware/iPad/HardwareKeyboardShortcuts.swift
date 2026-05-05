#if canImport(SwiftUI)
import SwiftUI

// MARK: - HardwareKeyboardShortcuts
//
// iPad keyboard shortcut wiring for the Hardware 3-column layout.
//
// Shortcuts:
//   ⌘T  — Fire the test action for the currently selected device type
//   ⌘R  — Rescan / refresh the paired devices list
//   ⌘P  — Print test page (printer-specific; noop for other device types)
//
// Usage: attach `.hardwareKeyboardShortcuts(...)` to `HardwareThreeColumnView`.

extension View {

    /// Attaches the three Hardware keyboard shortcuts to this view.
    ///
    /// - Parameters:
    ///   - selectedType: Currently selected device type in the sidebar.
    ///   - vm: Shared test-actions view-model.
    ///   - onRescan: Closure called on ⌘R to trigger a rescan / refresh.
    public func hardwareKeyboardShortcuts(
        selectedType: HardwareDeviceType?,
        vm: DeviceTestActionsViewModel,
        onRescan: @escaping () -> Void
    ) -> some View {
        self.modifier(
            HardwareKeyboardShortcutsModifier(
                selectedType: selectedType,
                vm: vm,
                onRescan: onRescan
            )
        )
    }
}

// MARK: - HardwareKeyboardShortcutsModifier

/// ViewModifier that injects ⌘T, ⌘R, ⌘P shortcuts.
///
/// ⌘T dispatches the appropriate test action for the currently selected device type.
/// ⌘R calls `onRescan` — callers wire this to a BLE scan or device list refresh.
/// ⌘P always fires `printTestPage()` regardless of selected type,
///     matching the mental model: "I want to print a test page right now."
public struct HardwareKeyboardShortcutsModifier: ViewModifier {

    let selectedType: HardwareDeviceType?
    @Bindable var vm: DeviceTestActionsViewModel
    let onRescan: () -> Void

    public func body(content: Content) -> some View {
        content
            .background {
                // Hidden button group — the standard SwiftUI pattern for
                // attaching keyboard shortcuts without visible controls.
                Group {
                    // ⌘T — test current device type
                    Button("") { fireTest() }
                        .keyboardShortcut("t", modifiers: .command)
                        .accessibilityHidden(true)

                    // ⌘R — rescan / refresh
                    Button("") { onRescan() }
                        .keyboardShortcut("r", modifiers: .command)
                        .accessibilityHidden(true)

                    // ⌘P — print test page (always printer, regardless of selected type)
                    Button("") { Task { await vm.printTestPage() } }
                        .keyboardShortcut("p", modifiers: .command)
                        .accessibilityHidden(true)
                }
                .opacity(0)
                .allowsHitTesting(false)
            }
    }

    // MARK: - Private

    private func fireTest() {
        guard let type = selectedType else { return }
        Task {
            switch type {
            case .printer:  await vm.printTestPage()
            case .drawer:   await vm.openDrawer()
            case .scale:    await vm.readScale()
            case .scanner:  await vm.testScanner()
            case .terminal: await vm.pingTerminal()
            }
        }
    }
}

// MARK: - HardwareShortcutDescriptions
//
// Structured descriptions used by the help overlay / tooltip in the detail column.

public struct HardwareShortcutDescription: Identifiable, Sendable {
    public let id: String
    public let key: String
    public let modifiers: String
    public let description: String

    public init(key: String, modifiers: String, description: String) {
        self.id = "\(modifiers)+\(key)"
        self.key = key
        self.modifiers = modifiers
        self.description = description
    }
}

public enum HardwareKeyboardShortcutCatalog {

    /// All shortcuts available in the Hardware 3-column layout.
    public static let all: [HardwareShortcutDescription] = [
        HardwareShortcutDescription(
            key: "T",
            modifiers: "⌘",
            description: "Test selected device type"
        ),
        HardwareShortcutDescription(
            key: "R",
            modifiers: "⌘",
            description: "Rescan / refresh device list"
        ),
        HardwareShortcutDescription(
            key: "P",
            modifiers: "⌘",
            description: "Print test page"
        )
    ]
}

#endif
