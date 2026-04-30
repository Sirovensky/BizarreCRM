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
///
/// **§16 — Tenant branding, language, privacy:**
/// The host app reads tenant config from Settings (§19) and pushes it here.
/// CFDView reads these fields to show the correct tagline, language, and
/// ensures no cashier-private data leaks to the customer display.
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

    /// `true` when the current cart is associated with a repair ticket
    /// (check-in / deposit flow). Drives repair-specific copy on the CFD
    /// so customers see "Your device is being checked in" instead of
    /// the generic cashier-wait message.
    public private(set) var hasRepairTicket: Bool = false

    // MARK: - §16 — Post-sale state

    /// When non-nil the CFD shows the thank-you / receipt state with this token
    /// for a QR code. Cleared by `clear()` or when a new cart starts.
    public private(set) var postSaleState: CFDPostSaleState? = nil

    // MARK: - §16 — Tenant branding

    /// Shop name shown in the CFD header. Pushed from tenant settings.
    public var shopName: String = "BizarreCRM"

    /// Optional tagline shown below the shop name in the CFD header.
    public var shopTagline: String = ""

    // MARK: - §16 — Language

    /// BCP-47 language tag for the customer display (e.g. "en", "es", "fr").
    /// Decoupled from the cashier's app locale. CFDView uses this to pick
    /// localised strings for CTA labels visible to the customer.
    public var customerLanguageCode: String = "en"

    // MARK: - §16 — Privacy

    /// When `true` the CFD must not display any cashier-private data:
    /// - cashier name or employee ID
    /// - other customers' details from prior transactions
    /// - employee personal information
    ///
    /// This is `true` by default and should only be set to `false` by an
    /// explicit admin action (e.g. a kiosk mode where a single employee runs
    /// the display).
    public var privacyModeEnabled: Bool = true

    /// Public init for unit tests. Production code uses `CFDBridge.shared`.
    public init() {}

    // MARK: - Public API

    /// Push the latest `Cart` state to the CFD display.
    /// Call this from the POS scene on every cart mutation.
    ///
    /// - Parameters:
    ///   - cart: The current POS cart.
    ///   - isRepairCheckIn: Pass `true` when the cart represents a repair
    ///     ticket check-in / deposit so the CFD shows repair-specific copy.
    public func update(from cart: Cart, isRepairCheckIn: Bool = false) {
        items = cart.items.map { item in
            CFDCartLine(
                id: item.id,
                name: item.name,
                quantity: item.quantity,
                lineTotalCents: item.lineSubtotalCents
            )
        }
        subtotalCents    = cart.subtotalCents
        taxCents         = cart.taxCents
        tipCents         = cart.tipCents
        totalCents       = cart.totalCents
        hasRepairTicket  = isRepairCheckIn
        // Clear post-sale state when a live cart arrives.
        postSaleState = nil
    }

    /// Show the thank-you / post-approval celebration state on the CFD.
    /// Call this from the POS scene immediately after a sale completes.
    ///
    /// - Parameters:
    ///   - trackingToken: Optional opaque token that becomes the QR code URL.
    ///   - googleReviewURL: Optional shop-configured Google review link shown
    ///     as a second QR code or text prompt.
    ///   - membershipSignupURL: Optional membership sign-up URL for the QR
    ///     alongside the tracking QR.
    public func showPostSale(
        trackingToken: String? = nil,
        googleReviewURL: URL? = nil,
        membershipSignupURL: URL? = nil
    ) {
        postSaleState = CFDPostSaleState(
            trackingToken: trackingToken,
            googleReviewURL: googleReviewURL,
            membershipSignupURL: membershipSignupURL
        )
        // Cart is cleared — customer sees the celebration screen, not cart rows.
        items         = []
        subtotalCents = 0
        taxCents      = 0
        tipCents      = 0
        totalCents    = 0
    }

    /// Reset the display to the idle / between-sales state.
    public func clear() {
        items           = []
        subtotalCents   = 0
        taxCents        = 0
        tipCents        = 0
        totalCents      = 0
        hasRepairTicket = false
        postSaleState   = nil
    }
}

// MARK: - CFDPostSaleState

/// §16 — Carries data for the post-approval "Thank you!" screen shown on the
/// customer-facing display. Auto-dismissed after 10s by `CFDView`.
public struct CFDPostSaleState: Equatable, Sendable {
    /// Opaque tracking token from the server invoice response. Encoded into the
    /// receipt QR code: `https://app.bizarrecrm.com/track/{token}`.
    public let trackingToken: String?
    /// Optional Google review URL (tenant-configured in Settings → POS → Display).
    public let googleReviewURL: URL?
    /// Optional membership sign-up URL (tenant-configured in Settings → Loyalty).
    public let membershipSignupURL: URL?

    public init(
        trackingToken: String? = nil,
        googleReviewURL: URL? = nil,
        membershipSignupURL: URL? = nil
    ) {
        self.trackingToken    = trackingToken
        self.googleReviewURL  = googleReviewURL
        self.membershipSignupURL = membershipSignupURL
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
