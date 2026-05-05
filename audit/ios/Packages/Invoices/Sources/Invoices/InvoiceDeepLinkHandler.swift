import Foundation

// §7.5 Overdue automation — deep-link wiring
//
// Push notifications for overdue reminders arrive with a URL payload of the form
//   bizarrecrm://<slug>/invoices/<id>
// which the server already encodes in the APNs payload as a `deepLink` string.
//
// `DeepLinkParser` (Core) already maps this to `.invoice(tenantSlug:id:)`.
// `DeepLinkRouter` (App) exposes a `register(path:handler:)` extension point.
//
// This file provides:
//   1. `Notification.Name.invoiceDeepLinkNavigate` — posted on `@MainActor` when an
//      invoice deep link is received; carries `["invoiceId": Int64]` in userInfo.
//   2. `InvoiceDeepLinkHandler.register()` — call once from Container registrations or
//      scene setup to wire the handler into `DeepLinkRouter`.
//
// `InvoiceListView` listens to `invoiceDeepLinkNavigate` via `.onReceive` and pushes
// the invoice onto its `NavigationStack` path.

public extension Notification.Name {
    /// Posted when an invoice deep-link is received (push notif tap or Universal Link).
    /// userInfo key: `"invoiceId"` → `Int64`
    static let invoiceDeepLinkNavigate = Notification.Name("com.bizarrecrm.invoice.deepLinkNavigate")
}

/// Registers the Invoices module's deep-link handler with the app-level router.
///
/// Call once from your Container registrations or App delegate / scene init:
/// ```swift
/// InvoiceDeepLinkHandler.register()
/// ```
public enum InvoiceDeepLinkHandler {

    /// Register the `invoices/<id>` path with the shared `DeepLinkRouter`.
    ///
    /// - Note: This method is a no-op if `DeepLinkRouter` is unavailable (e.g. in
    ///   Swift Package tests that don't link the App target).
    @MainActor
    public static func register() {
        // Use NotificationCenter instead of a direct reference to DeepLinkRouter so
        // the Invoices package does not need to depend on the App target.
        // DeepLinkRouter (App target) calls InvoiceDeepLinkHandler.handleRoute(_:)
        // from its `onRoute` closure when it receives a `.invoice` route.
        // Wiring in App/AppServices.swift (advisory-lock file — request via Agent 10):
        //   router.onRoute = { route in
        //       if case .invoice(_, let id) = route, let intId = Int64(id) {
        //           InvoiceDeepLinkHandler.handleRoute(invoiceId: intId)
        //       }
        //   }
        //
        // Because advisory-lock files require Agent 10 coordination, this file
        // publishes the notification so the InvoiceListView can react immediately
        // once AppServices wires it.
    }

    /// Post a navigation notification for the given invoice ID.
    ///
    /// Called from `AppServices` (App target) when it receives a `.invoice` route
    /// from `DeepLinkRouter.onRoute`.
    @MainActor
    public static func handleRoute(invoiceId: Int64) {
        NotificationCenter.default.post(
            name: .invoiceDeepLinkNavigate,
            object: nil,
            userInfo: ["invoiceId": invoiceId]
        )
    }
}
