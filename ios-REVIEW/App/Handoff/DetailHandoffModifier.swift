import SwiftUI

// MARK: - DetailHandoffModifier
//
// §22.4 — Multi-window detail handoff.
//
// When a detail view (ticket / customer / invoice) is visible in one iPad
// window the user should be able to "hand off" to a second window — or
// to a different Apple device — without losing context.
//
// This modifier:
//   1. Publishes a Handoff `NSUserActivity` while the view is on screen
//      (via `HandoffPublisher`), so macOS / other devices show the Handoff
//      icon in their dock/switcher.
//   2. Provides a "Open in New Window" context-menu item on iPadOS that calls
//      `MultiWindowCoordinator` to spawn a second scene carrying the same route.
//
// Usage:
// ```swift
// TicketDetailView(ticket: t)
//     .detailHandoff(
//         activityType: HandoffActivityType.ticketView,
//         title: "Ticket #\(t.displayId)",
//         deepLinkURL: URL(string: "bizarrecrm://acme/ticket/\(t.id)")!,
//         entityId: "\(t.id)"
//     )
// ```

public struct DetailHandoffModifier: ViewModifier {

    // MARK: - Properties

    let activityType: String
    let title: String
    let deepLinkURL: URL
    let entityId: String?

    @State private var handoffActivity: NSUserActivity?

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .onAppear  { advertise() }
            .onDisappear { teardown() }
            .contextMenu {
                // "Open in New Window" — iPad-only; ignored on iPhone.
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Button {
                        MultiWindowCoordinator.shared.openDetail(routeURL: deepLinkURL.absoluteString)
                    } label: {
                        Label("Open in New Window", systemImage: "uiwindow.split.2x1")
                    }
                }

                // "Copy Link" — sends the deep-link URL to the pasteboard so
                // users can paste it into Messages / Notes / another app.
                Button {
                    UIPasteboard.general.string = deepLinkURL.absoluteString
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
    }

    // MARK: - Helpers

    private func advertise() {
        handoffActivity = HandoffPublisher.shared.publish(
            activityType: activityType,
            title: title,
            deepLinkURL: deepLinkURL,
            entityId: entityId
        )
    }

    private func teardown() {
        handoffActivity?.invalidate()
        handoffActivity = nil
    }
}

// MARK: - View extension

public extension View {
    /// Advertises this detail view for Handoff and adds an "Open in New Window"
    /// context-menu item on iPad.
    ///
    /// - Parameters:
    ///   - activityType: One of the `HandoffActivityType` constants.
    ///   - title:        Human-readable title shown in the Handoff dock icon.
    ///   - deepLinkURL:  App deep-link URL (`bizarrecrm://…` or universal link).
    ///   - entityId:     Optional opaque entity ID stored in the activity.
    func detailHandoff(
        activityType: String,
        title: String,
        deepLinkURL: URL,
        entityId: String? = nil
    ) -> some View {
        modifier(DetailHandoffModifier(
            activityType: activityType,
            title: title,
            deepLinkURL: deepLinkURL,
            entityId: entityId
        ))
    }
}

// MARK: - MultiWindowCoordinator convenience

private extension MultiWindowCoordinator {
    /// Open an arbitrary route URL in a new iPad window.
    /// Routes that don't match ticket/customer/invoice fall through to the
    /// detail scene's `ContentUnavailableView` placeholder.
    func openDetail(routeURL: String) {
        if routeURL.contains("/ticket/") {
            let id = routeURL.components(separatedBy: "/ticket/").last ?? ""
            openTicketDetail(id: id)
        } else if routeURL.contains("/customer/") {
            let id = routeURL.components(separatedBy: "/customer/").last ?? ""
            openCustomerDetail(id: id)
        } else if routeURL.contains("/invoice/") {
            let id = routeURL.components(separatedBy: "/invoice/").last ?? ""
            openInvoiceDetail(id: id)
        }
        // Unknown routes: no-op — caller should provide a known deep-link URL.
    }
}
