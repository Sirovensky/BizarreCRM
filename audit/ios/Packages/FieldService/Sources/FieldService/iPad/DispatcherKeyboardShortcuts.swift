// §22 DispatcherKeyboardShortcuts — keyboard shortcuts for the iPad dispatcher console.
//
// ⌘N   — assign next unassigned job (focus first unassigned job)
// ⌘F   — find / clear all filters to show all jobs
// J    — select next job in list (no modifiers, no text field focus)
// K    — select previous job in list
//
// Implemented as a zero-size transparent background view so it can be attached
// to either the 3-column or compact layout via `.background(...)`.
//
// All shortcuts are documented in .commands for discoverability in the Help menu
// on iPadOS 15+ hardware keyboard overlay.

import SwiftUI
import DesignSystem

// MARK: - DispatcherKeyboardShortcuts

/// Attach as `.background(DispatcherKeyboardShortcuts(vm: vm))` on the root view.
struct DispatcherKeyboardShortcuts: View {

    @Bindable var vm: DispatcherConsoleViewModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            // ⌘N — assign next unassigned job
            .keyboardShortcut("n", modifiers: .command)
            .onReceive(NotificationCenter.default.publisher(for: .dispatcherAssignNext)) { _ in
                vm.assignNextUnassigned()
            }
            // ⌘F — find / clear filters
            .overlay(
                Group {
                    Button("") {
                        vm.findJobs()
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
                }
            )
            // ⌘N button
            .overlay(
                Group {
                    Button("") {
                        vm.assignNextUnassigned()
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
                }
            )
            // J — next job (no modifier)
            .overlay(
                Group {
                    Button("") {
                        vm.selectNextJob()
                    }
                    .keyboardShortcut("j", modifiers: [])
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
                }
            )
            // K — previous job (no modifier)
            .overlay(
                Group {
                    Button("") {
                        vm.selectPreviousJob()
                    }
                    .keyboardShortcut("k", modifiers: [])
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
                }
            )
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let dispatcherAssignNext = Notification.Name("com.bizarrecrm.dispatcher.assignNext")
    static let dispatcherFind       = Notification.Name("com.bizarrecrm.dispatcher.find")
}

// MARK: - KeyboardShortcutCatalog

/// Documents all dispatcher console keyboard shortcuts.
/// Rendered in a help sheet accessible from the toolbar.
public struct DispatcherShortcutsCatalog {
    public struct Entry: Identifiable, Sendable {
        public let id = UUID()
        public let symbol: String
        public let modifiers: String
        public let description: String
    }

    public static let entries: [Entry] = [
        Entry(symbol: "N", modifiers: "⌘",    description: "Assign next unassigned job"),
        Entry(symbol: "F", modifiers: "⌘",    description: "Find / clear all filters"),
        Entry(symbol: "J", modifiers: "",     description: "Select next job"),
        Entry(symbol: "K", modifiers: "",     description: "Select previous job"),
    ]
}

// MARK: - DispatcherShortcutsHelpSheet

/// Shown when user taps the keyboard icon in the toolbar.
public struct DispatcherShortcutsHelpSheet: View {

    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List(DispatcherShortcutsCatalog.entries) { entry in
                HStack(spacing: DesignTokens.Spacing.lg) {
                    Text(entry.modifiers + entry.symbol)
                        .font(.brandMono(size: 15))
                        .foregroundStyle(.bizarreOrange)
                        .frame(minWidth: 44, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(entry.description)
                        .font(.brandBodyMedium())
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
                .frame(minHeight: DesignTokens.Touch.minTargetSide)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.modifiers)\(entry.symbol): \(entry.description)")
            }
            .listStyle(.sidebar)
            .navigationTitle("Keyboard Shortcuts")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
