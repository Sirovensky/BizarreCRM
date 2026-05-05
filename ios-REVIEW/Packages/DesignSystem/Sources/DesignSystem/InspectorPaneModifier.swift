import SwiftUI

// §22.1 — Inspector pane (iOS 17 `.inspector`) for Ticket detail and
// Customer detail.
//
// The `.brandInspector(isPresented:content:)` modifier wraps the iOS 17
// `.inspector(isPresented:content:)` API and falls back to a half-height
// sheet on iOS 16 so shipping targets remain supported.
//
// Usage:
//   TicketDetailView()
//       .brandInspector(isPresented: $showInspector) {
//           TicketInspectorContent(ticket: ticket)
//       }

// MARK: - InspectorPaneModifier

/// Applies an inspector pane using iOS 17's `.inspector` API on supported OS
/// versions, and falls back to a sheet presentation on iOS 16 (§22.1).
///
/// On iPad the inspector appears as a right-side panel alongside the detail
/// content.  On iPhone / compact-width it slides up as a sheet.
@available(iOS 16, *)
public struct InspectorPaneModifier<InspectorContent: View>: ViewModifier {

    // MARK: - Properties

    @Binding public var isPresented: Bool
    private let inspectorContent: () -> InspectorContent

    // MARK: - Constants

    /// Ideal inspector column width on iPad (§22.1).
    public static var idealWidth: CGFloat { 320 }

    // MARK: - Init

    public init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> InspectorContent
    ) {
        self._isPresented = isPresented
        self.inspectorContent = content
    }

    // MARK: - Body

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .inspector(isPresented: $isPresented) {
                    inspectorContent()
                        .inspectorColumnWidth(
                            min: 280,
                            ideal: Self.idealWidth,
                            max: 400
                        )
                }
        } else {
            // iOS 16 fallback — half-height sheet.
            content
                .sheet(isPresented: $isPresented) {
                    inspectorContent()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
        }
    }
}

// MARK: - Toggle button

/// A toolbar button that toggles an inspector pane (§22.1).
///
/// ```swift
/// .toolbar {
///     ToolbarItem(placement: .topBarTrailing) {
///         InspectorToggleButton(isPresented: $showInspector)
///     }
/// }
/// ```
public struct InspectorToggleButton: View {

    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        Button {
            withAnimation { isPresented.toggle() }
        } label: {
            Label(
                isPresented ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.right"
            )
        }
        .accessibilityLabel(isPresented ? "Hide Inspector" : "Show Inspector")
    }
}

// MARK: - View extension

public extension View {
    /// Attaches a brand inspector pane (§22.1).
    ///
    /// On iOS 17+ renders as a native right-side inspector column.
    /// On iOS 16 falls back to a resizable sheet.
    ///
    /// - Parameters:
    ///   - isPresented: Binding that controls panel visibility.
    ///   - content: The inspector panel contents.
    @available(iOS 16, *)
    func brandInspector<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(InspectorPaneModifier(isPresented: isPresented, content: content))
    }
}
