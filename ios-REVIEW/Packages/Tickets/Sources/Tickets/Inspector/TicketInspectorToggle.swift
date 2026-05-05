#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// §22.1 — Inspector toggle toolbar button.
//
// Placed in the navigation toolbar to show/hide the `.inspector` pane on iPad.
// Uses Liquid Glass on the toolbar chrome only (not on content).
// Hidden on iPhone (compact horizontal size class) because `.inspector`
// is iPad-only and shows as a sheet on compact layouts, which we opt out of.

public struct TicketInspectorToggle: View {
    @Binding var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(
                isPresented ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.right"
            )
            .symbolVariant(isPresented ? .fill : .none)
        }
        .brandGlass(.clear, in: Capsule())
        .accessibilityLabel(isPresented ? "Hide inspector panel" : "Show inspector panel")
        .accessibilityHint("Toggles the quick-edit inspector pane")
        .keyboardShortcut("i", modifiers: [.command, .shift])
    }
}

// MARK: - View modifier for easy wiring

/// Attaches the `.inspector` modifier and the toggle button in one call.
/// Usage:
/// ```swift
/// someView
///     .ticketInspector(isPresented: $showInspector, vm: inspectorVM, api: api)
/// ```
public extension View {
    @ViewBuilder
    func ticketInspector(
        isPresented: Binding<Bool>,
        vm: TicketInspectorViewModel,
        api: any APIClient
    ) -> some View {
        self
            .inspector(isPresented: isPresented) {
                TicketInspectorView(vm: vm, api: api)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
            }
    }
}
#endif
