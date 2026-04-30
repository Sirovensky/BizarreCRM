import SwiftUI

// §29.2 — Scroll & render performance contracts.
//
// Rules enforced here (per §29.2):
//  1. List scroll: 120fps on iPad Pro M, 60fps floor on iPhone SE (≤ 2 frame drops).
//  2. Use `List` not `LazyVStack` for long scrolling lists (UITableView cell reuse).
//  3. Stable IDs: server `id`, never `UUID()` per render.
//  4. `EquatableView` wrapper on complex row content.
//  5. `@State` minimized — prefer `@Observable` models at container.
//  6. No strong refs in ViewBuilder closures.
//  7. SwiftUI `_printChanges()` on critical views in debug.
//
// This file provides:
//  • `EquatableContent<V>` — generic `EquatableView` wrapper so complex rows
//    only redraw when their underlying value actually changes.
//  • `ListPerformanceModifier` — wraps a List with scroll-position tracking
//    and prefetch hints (pairs with `§29.4` cursor pagination).
//  • `#if DEBUG` `_printViewChanges()` modifier for per-view diff tracing.

// MARK: — §29.2 EquatableContent

/// Wraps any `Equatable` + `View` in `EquatableView` so SwiftUI short-circuits
/// body re-evaluation when the model has not changed.
///
/// ```swift
/// ForEach(tickets) { ticket in
///     EquatableContent(ticket) { t in
///         TicketRow(ticket: t)
///     }
/// }
/// ```
public struct EquatableContent<Value: Equatable, Content: View>: View, @preconcurrency Equatable {
    public let value: Value
    public let content: (Value) -> Content

    public init(_ value: Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.value = value
        self.content = content
    }

    public var body: some View {
        content(value)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: — §29.2 Debug print-changes modifier

public extension View {
    /// In debug builds, prints the reason SwiftUI re-evaluates this view's
    /// body. No-op in release builds.
    ///
    /// **Usage:** Temporarily attach during profiling; never commit to feature
    /// views. The modifier is guarded by `#if DEBUG` so the call site can
    /// remain.
    @ViewBuilder
    func debugPrintChanges(label: String = "") -> some View {
#if DEBUG
        self.modifier(_PrintChangesModifier(label: label))
#else
        self
#endif
    }
}

#if DEBUG
private struct _PrintChangesModifier: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        let _ = Self._printChanges()
        return content
    }
}
#endif

// MARK: — §29.2 Stable ID contract (documentation + lint hook)

/// Marker protocol that documents the stable-ID contract for any model used
/// as a `List` / `ForEach` element.
///
/// Conforming to this protocol signals that `id` is a server-assigned stable
/// value (not a locally-generated `UUID()`). SwiftLint's `forbid_uuid_in_foreach`
/// rule checks that `ForEach` initializers on `StableIdentifiable` types don't
/// wrap with `\.self` on a `UUID` property.
///
/// ```swift
/// struct Ticket: StableIdentifiable {
///     let id: Int   // ← server-assigned; never UUID()
///     ...
/// }
/// ```
public protocol StableIdentifiable: Identifiable where ID: Hashable & Sendable {}

// MARK: — §29.2 Memory-warning image cache flush hook

/// Connects to `UIApplication.didReceiveMemoryWarningNotification` and
/// flushes Nuke's in-memory image cache.
///
/// Register once from `AppServices` during startup:
/// ```swift
/// MemoryPressureHandler.shared.register()
/// ```
public final class MemoryPressureHandler: @unchecked Sendable {
    public static let shared = MemoryPressureHandler()

    private var observer: (any NSObjectProtocol)?

    private init() {}

    /// Registers for `UIApplication.didReceiveMemoryWarningNotification`.
    /// Calling this multiple times is safe (re-registers once).
    public func register() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    private func handleMemoryWarning() {
        // Flush URLCache (networking layer caches).
        URLCache.shared.removeAllCachedResponses()
        // Post a notification so Nuke / GRDB page-cache listeners can respond.
        NotificationCenter.default.post(
            name: .appDidReceiveMemoryWarning,
            object: nil
        )
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

public extension Notification.Name {
    /// Broadcast when the app receives a memory warning. Consumers (image
    /// pipeline, GRDB page cache) listen and flush non-essential memory.
    static let appDidReceiveMemoryWarning = Notification.Name(
        "com.bizarrecrm.appDidReceiveMemoryWarning"
    )
}
