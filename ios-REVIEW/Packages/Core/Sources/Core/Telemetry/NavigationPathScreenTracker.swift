import SwiftUI

// §32.4 — Auto screen-view tracking for NavigationStack-based flows.
//
// Attach `.trackNavigationPath(_:nameFor:)` to any `NavigationStack` view to
// automatically emit `screen.viewed` events as the navigation path changes.
// Each push emits an appear event; each pop emits a disappear + duration event.
//
// Usage:
// ```swift
// NavigationStack(path: $router.path) {
//     TicketListView()
//         .navigationDestination(for: TicketRoute.self) { route in
//             TicketDetailView(route: route)
//         }
// }
// .trackNavigationPath($router.path) { route in
//     (route as? TicketRoute).map { "tickets.detail" } ?? "unknown"
// }
// ```
//
// All screen names are developer-supplied string literals — no PII passes through
// this helper. Route values are mapped to names by the `nameFor` closure before
// the event is fired.

// MARK: - NavigationPathScreenTracker

/// Observes a `NavigationPath` binding and emits §32.4 `screen.viewed` events
/// on push and pop transitions.
@MainActor
public struct NavigationPathScreenTracker<Route: Hashable>: ViewModifier {

    @Binding private var path: [Route]
    private let nameFor: (Route) -> String

    /// Timestamps keyed by the screen name + depth, so we can emit duration_ms on pop.
    @State private var appearTimes: [String: Date] = [:]

    public init(path: Binding<[Route]>, nameFor: @escaping (Route) -> String) {
        self._path = path
        self.nameFor = nameFor
    }

    public func body(content: Content) -> some View {
        content
            .onChange(of: path) { oldPath, newPath in
                handleTransition(from: oldPath, to: newPath)
            }
    }

    // MARK: - Private

    private func handleTransition(from oldPath: [Route], to newPath: [Route]) {
        if newPath.count > oldPath.count {
            // Push — emit appear for each newly added route.
            let pushed = newPath.dropFirst(oldPath.count)
            for route in pushed {
                let name = nameFor(route)
                let key = appearKey(name: name, depth: newPath.count - 1)
                appearTimes[key] = Date()
                Analytics.track(.screenViewed, properties: [
                    "screen": .string(name),
                    "nav_depth": .int(newPath.count)
                ])
            }
        } else if newPath.count < oldPath.count {
            // Pop — emit disappear + duration_ms for each removed route.
            let popped = oldPath.dropFirst(newPath.count)
            let baseDepth = oldPath.count - 1
            for (offset, route) in popped.enumerated() {
                let name = nameFor(route)
                let depth = baseDepth - offset
                let key = appearKey(name: name, depth: depth)
                let durationMs: Int
                if let start = appearTimes.removeValue(forKey: key) {
                    durationMs = Int(Date().timeIntervalSince(start) * 1_000)
                } else {
                    durationMs = 0
                }
                Analytics.track(.screenViewed, properties: [
                    "screen": .string(name),
                    "nav_depth": .int(depth),
                    "duration_ms": .int(durationMs),
                    "event_subtype": .string("disappear")
                ])
            }
        }
        // Replacement (same depth) — treated as a pop + push pair by callers;
        // we don't attempt to match here because route identity is opaque.
    }

    private func appearKey(name: String, depth: Int) -> String {
        "\(name)@\(depth)"
    }
}

// MARK: - View extension

public extension View {

    /// §32.4 — Automatically emit `screen.viewed` events when a `NavigationStack`
    /// path array changes.
    ///
    /// - Parameters:
    ///   - path: The `Binding<[Route]>` passed to the enclosing `NavigationStack`.
    ///   - nameFor: Closure mapping a route value to a dot-notation screen name
    ///              (e.g. `"tickets.detail"`). Must not include PII.
    ///
    /// ```swift
    /// NavigationStack(path: $path) { ... }
    ///     .trackNavigationPath($path) { route in
    ///         switch route {
    ///         case .ticketDetail: return "tickets.detail"
    ///         case .customerDetail: return "customers.detail"
    ///         }
    ///     }
    /// ```
    func trackNavigationPath<Route: Hashable>(
        _ path: Binding<[Route]>,
        nameFor: @escaping (Route) -> String
    ) -> some View {
        modifier(NavigationPathScreenTracker(path: path, nameFor: nameFor))
    }
}
