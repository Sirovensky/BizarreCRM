#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - SwitchUserSettingsRow
//
// §2.5 — Settings row + toolbar long-press entry point for switching user
// on a shared device via PIN. Exposed as a reusable row so both the Settings
// screen and the nav toolbar can present the same flow.
//
// The row is only visible when SharedDeviceManager.isSharedDevice is true.

public struct SwitchUserSettingsRow: View {
    @State private var showSheet: Bool = false
    private let onSwitched: ((String) -> Void)?

    public init(onSwitched: ((String) -> Void)? = nil) {
        self.onSwitched = onSwitched
    }

    public var body: some View {
        Button {
            showSheet = true
        } label: {
            Label("Switch user", systemImage: "person.2.circle")
        }
        .sheet(isPresented: $showSheet) {
            SwitchUserSheet(onSwitched: { token in
                showSheet = false
                onSwitched?(token)
            }, onCancel: {
                showSheet = false
            })
        }
        .accessibilityIdentifier("settings.switchUser")
    }
}

// MARK: - Switch User Sheet

/// Full-screen PIN entry sheet for switching to another staff member.
/// Uses the existing PinSwitchService + MultiUserRoster from the QuickSwitch package.
private struct SwitchUserSheet: View {
    let onSwitched: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            PinPadView(
                onSwitched: onSwitched,
                onCancel: onCancel
            )
            .navigationTitle("Switch user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Toolbar avatar long-press modifier

/// Adds a "Switch user" action to a toolbar icon long-press.
private struct SwitchUserToolbarModifier: ViewModifier {
    @State private var showSheet: Bool = false
    private let onSwitched: ((String) -> Void)?

    init(onSwitched: ((String) -> Void)?) {
        self.onSwitched = onSwitched
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    showSheet = true
                } label: {
                    Label("Switch user", systemImage: "person.2.circle")
                }
            }
            .sheet(isPresented: $showSheet) {
                SwitchUserSheet(
                    onSwitched: { token in
                        showSheet = false
                        onSwitched?(token)
                    },
                    onCancel: { showSheet = false }
                )
            }
    }
}

public extension View {
    /// Adds a "Switch user" long-press context menu to a toolbar avatar icon.
    /// The switch sheet is only shown on shared-device iPads.
    func switchUserLongPress(onSwitched: ((String) -> Void)? = nil) -> some View {
        modifier(SwitchUserToolbarModifier(onSwitched: onSwitched))
    }
}

#endif
