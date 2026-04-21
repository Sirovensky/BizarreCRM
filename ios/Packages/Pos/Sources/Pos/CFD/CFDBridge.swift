import Foundation
import Observation

/// §16 CFD — Connects the host app's `Cart` to the secondary
/// Customer-Facing Display scene.
///
/// **Thread safety:** `@MainActor` throughout; the host must call
/// `update(from:)` on the main actor after each cart mutation.
///
/// **Scene wiring (BizarreCRMApp.swift — DO NOT edit that file):**
/// ```swift
/// WindowGroup(id: "cfd") {
///     CFDView()
///         .environment(CFDBridge.shared)
/// }
/// .handlesExternalEvents(matching: ["cfd"])
/// ```
/// The `"cfd"` `WindowGroup` opens on secondary display / Sidecar / AirPlay.
/// The `CFDBridge` singleton is available via the environment in `CFDView`.
///
/// **Update from the POS host scene on each cart mutation:**
/// ```swift
/// .onChange(of: cart.items) {
///     CFDBridge.shared.update(from: cart)
/// }
/// ```
/// Clear on sale completion / cart clear:
/// ```swift
/// CFDBridge.shared.clear()
/// ```
@MainActor
@Observable
public final class CFDBridge {

    // MARK: - Singleton

    public static let shared = CFDBridge()

    // MARK: - Observed state (read by CFDView)

    /// Live snapshot of cart items forwarded from the host scene.
    /// Empty array means the display is idle.
    public private(set) var items: [CFDCartLine] = []

    /// Subtotal in cents.
    public private(set) var subtotalCents: Int = 0

    /// Tax in cents.
    public private(set) var taxCents: Int = 0

    /// Tip in cents.
    public private(set) var tipCents: Int = 0

    /// Grand total in cents.
    public private(set) var totalCents: Int = 0

    /// `true` when at least one item is in the cart.
    public var isActive: Bool { !items.isEmpty }

    /// Public init for unit tests. Production code uses `CFDBridge.shared`.
    public init() {}

    // MARK: - Public API

    /// Push the latest `Cart` state to the CFD display.
    /// Call this from the POS scene on every cart mutation.
    public func update(from cart: Cart) {
        items = cart.items.map { item in
            CFDCartLine(
                id: item.id,
                name: item.name,
                quantity: item.quantity,
                lineTotalCents: item.lineSubtotalCents
            )
        }
        subtotalCents = cart.subtotalCents
        taxCents      = cart.taxCents
        tipCents      = cart.tipCents
        totalCents    = cart.totalCents
    }

    /// Reset the display to the idle / between-sales state.
    public func clear() {
        items         = []
        subtotalCents = 0
        taxCents      = 0
        tipCents      = 0
        totalCents    = 0
    }
}

// MARK: - CFDCartLine

/// A lightweight, `Sendable` snapshot of a single line for the CFD display.
/// Strips unit price — only the formatted line total is shown to the customer.
public struct CFDCartLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let quantity: Int
    public let lineTotalCents: Int

    public init(id: UUID = UUID(), name: String, quantity: Int, lineTotalCents: Int) {
        self.id             = id
        self.name           = name
        self.quantity       = quantity
        self.lineTotalCents = lineTotalCents
    }
}
