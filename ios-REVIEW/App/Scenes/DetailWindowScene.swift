import SwiftUI
import Core

// MARK: - DetailWindowScene

/// Standalone SwiftUI `View` that acts as the root content of a
/// secondary "detail" window opened by `MultiWindowCoordinator`.
///
/// **How to wire into `BizarreCRMApp.swift`:**
/// ```swift
/// WindowGroup(id: "detail", for: DeepLinkRoute.self) { $route in
///     DetailWindowScene(route: route)
///         .environment(appState)
///         .tint(.bizarreOrange)
/// }
/// ```
///
/// The `WindowGroup(id:for:)` form is available on iOS 16 + iPadOS 16.
/// On devices that don't support multiple scenes the group is silently
/// ignored and the record stays reachable via normal in-app navigation.
public struct DetailWindowScene: View {

    /// The route decoded from the incoming `NSUserActivity` / URL.
    /// May be `nil` while the scene is still loading.
    public let route: DeepLinkRoute?

    @Environment(AppState.self) private var appState

    public init(route: DeepLinkRoute?) {
        self.route = route
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let route {
            routedView(for: route)
        } else {
            placeholderView
        }
    }

    @ViewBuilder
    private func routedView(for route: DeepLinkRoute) -> some View {
        switch route {
        case .ticket(_, let id):
            // Ticket detail view — wired to TicketRepositoryImpl upstream.
            // The label is purely informational; the real view is injected
            // by the feature package once it is instantiated.
            Text("Ticket \(id)")
                .navigationTitle("Ticket")
                .accessibilityLabel("Ticket detail for ID \(id)")

        case .customer(_, let id):
            Text("Customer \(id)")
                .navigationTitle("Customer")
                .accessibilityLabel("Customer detail for ID \(id)")

        case .invoice(_, let id):
            Text("Invoice \(id)")
                .navigationTitle("Invoice")
                .accessibilityLabel("Invoice detail for ID \(id)")

        default:
            placeholderView
        }
    }

    private var placeholderView: some View {
        ContentUnavailableView(
            "No Content",
            systemImage: "doc.text",
            description: Text("Open a ticket, customer, or invoice to view it here.")
        )
        .accessibilityLabel("No detail content selected")
    }
}
