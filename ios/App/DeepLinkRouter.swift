import Foundation
import Observation
import Core

// Re-export the route enum so callers only need to import the App target.
@_exported import enum   Core.DeepLinkRoute    // DeepLinkRoute enum lives in Core
@_exported import enum   Core.DeepLinkParser   // parser enum lives in Core

// MARK: - DeepLinkRouter

/// `@MainActor` routing hub for the app.
///
/// **Architecture**
/// - Parsing logic lives in `Core.DeepLinkParser` (pure, UIKit-free, `swift test`-able).
/// - `DeepLinkRouter` is the thin `@MainActor` + `@Observable` shell that:
///   - holds `pending` state observed by `RootView`,
///   - calls `onRoute` for imperative subscribers (e.g. AppServices),
///   - exposes `register(path:handler:)` for feature modules that need custom
///     handling without touching this file.
///
/// **Wiring (do NOT change in this file — handled at merge)**
///
/// `BizarreCRMApp.swift` integration:
/// ```swift
/// .onOpenURL { url in
///     DeepLinkRouter.shared.handle(url)
/// }
/// .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
///     guard let url = activity.webpageURL else { return }
///     DeepLinkRouter.shared.handle(url)
/// }
/// ```
///
/// `RootView.swift` integration:
/// ```swift
/// @Environment(DeepLinkRouter.self) var router
///
/// .onChange(of: router.pending) { _, route in
///     guard let route else { return }
///     navigateTo(route)          // your NavigationPath / selection logic
///     router.consume()
/// }
/// ```
///
/// **Info.plist requirements** (managed by `scripts/write-info-plist.sh`):
/// ```xml
/// <key>CFBundleURLTypes</key>
/// <array>
///   <dict>
///     <key>CFBundleURLSchemes</key>
///     <array><string>bizarrecrm</string></array>
///   </dict>
/// </array>
/// ```
///
/// **Associated Domains entitlement** (managed by `BizarreCRM.entitlements`):
/// ```
/// applinks:app.bizarrecrm.com
/// applinks:*.bizarrecrm.com
/// ```
/// Self-hosted tenant subdomains are NOT listed — they use the `bizarrecrm://`
/// custom scheme instead (re-signing per tenant is not scalable).
@MainActor
@Observable
public final class DeepLinkRouter {

    // MARK: Singleton

    public static let shared = DeepLinkRouter()

    // MARK: State

    /// The last parsed route that has not yet been consumed by the UI.
    public private(set) var pending: DeepLinkRoute?

    // MARK: Handlers

    /// Closure registered by `AppServices` / `RootView` for imperative dispatch.
    /// Called synchronously after `pending` is set.
    public var onRoute: (@MainActor (DeepLinkRoute) -> Void)?

    /// Called when an inbound URL resolves to `.unknown`.
    ///
    /// The default implementation logs at `.warning` level.
    /// The App layer can replace this with a toast/snackbar dismissal:
    /// ```swift
    /// DeepLinkRouter.shared.onUnknownRoute = { url in
    ///     ToastManager.shared.show("Unknown deep link: \(url.path)", style: .warning)
    /// }
    /// ```
    public var onUnknownRoute: (@MainActor (URL) -> Void)?

    /// Custom path handlers registered by feature modules via
    /// `DeepLinkRouter.register(path:handler:)`.  Key is a lowercase path
    /// prefix, e.g. `"pos"` or `"tickets/new"`.
    private var customHandlers: [String: @MainActor (URL) -> Void] = [:]

    // MARK: Init

    private init() {}

    // MARK: Public API

    /// Handle an incoming URL from `onOpenURL` or `onContinueUserActivity`.
    public func handle(_ url: URL) {
        // Check custom handlers first so feature modules can override.
        if let handler = matchCustomHandler(for: url) {
            handler(url)
            return
        }
        let route = Core.DeepLinkParser.parse(url)

        // Unknown-route fallback: log + invoke `onUnknownRoute` instead of
        // silently setting `pending` to an unroutable `.unknown` value.
        if case .unknown = route {
            AppLog.routing.warning(
                "DeepLinkRouter: unrecognised route — \(url.absoluteString, privacy: .public)"
            )
            if let fallback = onUnknownRoute {
                fallback(url)
            }
            // Do not set `pending` — the UI has nothing to navigate to.
            return
        }

        pending = route
        onRoute?(route)
    }

    /// Mark the current `pending` route as consumed.
    ///
    /// Call this after the UI has navigated in response to `pending`.
    @discardableResult
    public func consume() -> DeepLinkRoute? {
        defer { pending = nil }
        return pending
    }

    // MARK: Extension point

    /// Register a custom handler for a specific URL path prefix.
    ///
    /// Feature modules call this from their `init` or `Container` registration
    /// to intercept URLs before the default parse logic runs.
    ///
    /// Example (from a feature module):
    /// ```swift
    /// DeepLinkRouter.shared.register(path: "pos/scanner") { url in
    ///     BarcodeScanner.launch()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - path: Lowercase path prefix after the slug,
    ///           e.g. `"pos/scanner"` matches `bizarrecrm://<slug>/pos/scanner`.
    ///   - handler: Called on the `@MainActor` when the path is matched.
    public func register(path: String, handler: @escaping @MainActor (URL) -> Void) {
        customHandlers[path.lowercased()] = handler
    }

    // MARK: Helpers

    private func matchCustomHandler(for url: URL) -> (@MainActor (URL) -> Void)? {
        // Build the "resource/id" portion of the URL path so we can match
        // against registered prefixes.
        let parts = url.pathComponents.filter { $0 != "/" }
        // Skip slug (first host component for bizarrecrm://, or first path
        // segment for universal links).
        let pathAfterSlug: String
        if url.scheme?.lowercased() == "bizarrecrm" {
            pathAfterSlug = parts.joined(separator: "/")
        } else {
            // Universal link — first path segment is the slug.
            pathAfterSlug = parts.dropFirst().joined(separator: "/")
        }
        let lower = pathAfterSlug.lowercased()

        // Longest-prefix wins.
        return customHandlers
            .filter { lower.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }
            .map { $0.value }
    }
}
