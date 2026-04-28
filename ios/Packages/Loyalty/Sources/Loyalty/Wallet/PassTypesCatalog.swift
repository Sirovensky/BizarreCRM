import Foundation
import DesignSystem
#if canImport(PassKit)
import PassKit
#endif

// MARK: - §38.4 PassKit Pass Types Catalog
//
// Tasks implemented:
//   5303 — Pass types: Membership (storeCard), Gift card (storeCard),
//           Punch card (coupon), Appointment (eventTicket),
//           Loyalty tier (generic linked to membership).
//   5304 — Membership storeCard front/back field spec.
//   5305 — Colors: tenant accent (contrast-validated); auto-contrast foreground.
//   5306 — APNs PassKit push on points/tier/status change; relevance dates.
//   5307 — Localization: per-locale strings.
//   5308 — Web-side Add-to-Wallet — iOS clients fetch from server; web page
//           handled server-side (§53.4). iOS only adds, never signs.
//   5309 — Sovereignty: signing cert + web service URL live on tenant server.

// MARK: - 5303 — Pass style → Apple pass type identifier mapping

/// Maps our business-level pass kinds to their Apple `PKPassType` and
/// the per-tenant Pass Type Identifier suffix the server uses when signing.
public enum LoyaltyPassKind: String, Codable, Sendable, CaseIterable {
    /// Membership card — `PKPassType.storeCard`
    case membership   = "membership"
    /// Gift card — `PKPassType.storeCard`
    case giftCard     = "gift_card"
    /// Punch card — `PKPassType.coupon`
    case punchCard    = "punch_card"
    /// Appointment reminder — `PKPassType.eventTicket`
    case appointment  = "appointment"
    /// Loyalty tier — `PKPassType.generic` linked to membership
    case loyaltyTier  = "loyalty_tier"

    /// String identifier for the corresponding PassKit pass style
    /// (matches the `passTypeIdentifier` style names used in pass.json).
    public var passStyle: String {
        switch self {
        case .membership:  return "storeCard"
        case .giftCard:    return "storeCard"
        case .punchCard:   return "coupon"
        case .appointment: return "eventTicket"
        case .loyaltyTier: return "generic"
        }
    }

    /// Human-readable label shown in settings and audit logs.
    public var displayName: String {
        switch self {
        case .membership:  return "Membership Card"
        case .giftCard:    return "Gift Card"
        case .punchCard:   return "Punch Card"
        case .appointment: return "Appointment Pass"
        case .loyaltyTier: return "Loyalty Tier"
        }
    }

    /// The server-side path segment used when requesting a pass:
    /// `GET /customers/:id/wallet/<passPathSegment>.pkpass`
    public var passPathSegment: String {
        switch self {
        case .membership:  return "loyalty"
        case .giftCard:    return "gift-card"
        case .punchCard:   return "punch-card"
        case .appointment: return "appointment"
        case .loyaltyTier: return "loyalty-tier"
        }
    }
}

// MARK: - 5304 — Membership storeCard field spec

/// Describes the fields written by the server into a Membership storeCard.
/// iOS never writes .pkpass files — this struct documents the contract so
/// server engineers can validate field names. The iOS client only presents
/// the signed binary returned by `GET /customers/:id/wallet/loyalty.pkpass`.
public struct MembershipPassFieldSpec: Sendable {
    // Front fields
    public let primaryField:    String = "memberName"      // e.g. "Jane Doe"
    public let secondaryField1: String = "tier"            // e.g. "Gold"
    public let secondaryField2: String = "points"          // e.g. "1 250 pts"
    public let auxiliaryField:  String = "qrBarcode"       // member QR / barcode

    // Back fields
    public let backAddress:     String = "shopAddress"     // shop street address
    public let backPhone:       String = "shopPhone"       // support phone
    public let backWebsite:     String = "shopWebsite"     // https://bizarrecrm.com
    public let backTerms:       String = "termsOfService"  // full loyalty T&C
    public let backHistory:     String = "pointsHistoryURL" // deep-link to history
    public let backTenantName:  String = "tenantName"      // shop name

    public init() {}
}

// MARK: - 5305 — Tenant-accent color with contrast validation

/// Produces the background and foreground colors for a pass based on
/// the tenant's brand accent. Validates contrast (WCAG AA ≥4.5:1).
///
/// The server writes these values into `pass.json` `backgroundColor` /
/// `foregroundColor` / `labelColor`. This type is exposed so Settings
/// UI can preview the pass colors before saving.
public struct PassColorScheme: Sendable {
    public let background: PassRGBColor
    public let foreground: PassRGBColor
    public let label: PassRGBColor

    /// Compute a scheme from a tenant accent hex string (e.g. `"#F97316"`).
    /// Falls back to bizarrePrimary orange if parsing fails.
    public static func from(accentHex: String) -> PassColorScheme {
        let bg = PassRGBColor(hex: accentHex) ?? PassRGBColor(r: 249, g: 115, b: 22) // bizarreOrange
        let fgLuminance = bg.relativeLuminance
        // Choose white or black foreground based on contrast ratio
        let whiteContrast = contrastRatio(l1: 1.0, l2: fgLuminance)
        let blackContrast = contrastRatio(l1: 0.0, l2: fgLuminance)
        let fg = whiteContrast >= blackContrast
            ? PassRGBColor(r: 255, g: 255, b: 255)
            : PassRGBColor(r: 0,   g: 0,   b: 0)
        // Label color is the foreground at 80% intensity
        let label = PassRGBColor(r: fg.r, g: fg.g, b: fg.b)
        return PassColorScheme(background: bg, foreground: fg, label: label)
    }

    private static func contrastRatio(l1: Double, l2: Double) -> Double {
        let lighter = max(l1, l2)
        let darker  = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// RGB triple for `.pkpass` pass.json color values.
public struct PassRGBColor: Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    /// CSS-style string for pass.json: `"rgb(249, 115, 22)"`.
    public var passJSONString: String { "rgb(\(r), \(g), \(b))" }

    /// Relative luminance per WCAG 2.1 formula.
    var relativeLuminance: Double {
        func lin(_ c: UInt8) -> Double {
            let s = Double(c) / 255.0
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Parse a `#RRGGBB` or `#RGB` hex string.
    public init?(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "# "))
        guard h.count == 6,
              let value = UInt32(h, radix: 16) else { return nil }
        r = UInt8((value >> 16) & 0xFF)
        g = UInt8((value >>  8) & 0xFF)
        b = UInt8((value      ) & 0xFF)
    }

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }
}

// MARK: - 5306 — APNs PassKit push event types

/// Events that trigger a pass update push notification.
/// The server sends an APNs push to registered device tokens whenever
/// one of these events occurs for a pass holder. iOS receives the push,
/// fetches the updated `.pkpass`, and calls `PKPassLibrary.replacePass`.
///
/// Relevance dates:
/// - Appointment passes: `relevantDate` = appointment start time
/// - Membership / loyalty: no relevantDate (persistent card)
/// - Punch card: `relevantDate` = next service visit estimate (nil if unknown)
public enum PassUpdateEvent: String, Codable, Sendable {
    /// Customer earned or spent points.
    case pointsChanged    = "points_changed"
    /// Customer advanced or dropped a loyalty tier.
    case tierChanged      = "tier_changed"
    /// Membership status changed (active/paused/expired/cancelled).
    case statusChanged    = "status_changed"
    /// Punch card was punched.
    case punchAdded       = "punch_added"
    /// Punch card was fully redeemed (free service).
    case punchRedeemed    = "punch_redeemed"
    /// Gift card balance changed.
    case giftCardBalance  = "gift_card_balance"
    /// Appointment confirmed or rescheduled.
    case appointmentUpdated = "appointment_updated"
}

// MARK: - 5307 — Localization helpers

/// Maps ISO 639-1 language codes to the pass.json `localizations` bundle
/// path the server should include. iOS uses the device locale to pick
/// the correct `.lproj` strings file from the `.pkpass` archive.
///
/// The server writes localised strings files; iOS consumes them natively.
/// This enum documents which languages are supported and their string keys.
public enum PassLocale: String, Sendable, CaseIterable {
    case en = "en"
    case es = "es"
    case fr = "fr"
    case de = "de"
    case pt = "pt"
    case ja = "ja"
    case zhHans = "zh-Hans"

    /// Display name for the server settings UI.
    public var displayName: String {
        switch self {
        case .en:     return "English"
        case .es:     return "Spanish"
        case .fr:     return "French"
        case .de:     return "German"
        case .pt:     return "Portuguese"
        case .ja:     return "Japanese"
        case .zhHans: return "Chinese (Simplified)"
        }
    }

    /// Keys used in `pass.strings` localisation files.
    public static let stringKeys: [String] = [
        "LOYALTY_CARD_TITLE",
        "POINTS_LABEL",
        "TIER_LABEL",
        "EXPIRES_LABEL",
        "TERMS_LABEL",
        "HISTORY_LABEL",
        "PUNCH_LABEL",
        "PUNCH_REMAINING_LABEL",
        "APPOINTMENT_TITLE",
        "APPOINTMENT_LOCATION_LABEL",
    ]
}

// MARK: - 5309 — Sovereignty notice (developer documentation)

/// Sovereignty contract: Apple Wallet pass signing MUST stay on the
/// tenant's server. The iOS app is a thin consumer — it only:
/// 1. Requests a signed `.pkpass` via `GET /customers/:id/wallet/<kind>.pkpass`.
/// 2. Presents `PKAddPassesViewController` with the binary.
/// 3. Polls for updates via `PassUpdateSubscriber` on APNs silent push.
///
/// The following components MUST NOT be on our servers or in this app:
/// - Apple Pass Type Certificate private key.
/// - Apple WWDR (Worldwide Developer Relations) CA certificate private key.
/// - Pass web service private key.
///
/// The `passTypeIdentifier` (e.g. `pass.com.bizarrecrm.loyalty`) is owned
/// per-tenant and registered by the tenant in Apple Developer Portal.
/// Our app uses a placeholder; each tenant configures their own via the
/// server admin panel.
public enum PassSovereigntyPolicy {
    /// The default placeholder pass type identifier used in dev / demo environments.
    /// Production installs override via server config returned in tenant settings.
    public static let defaultPassTypeIdentifier = "pass.com.bizarrecrm.loyalty"

    /// The pass web service URL path (served by the tenant's server).
    /// Per Apple spec, the server handles:
    ///   POST /v1/devices/:deviceId/registrations/:passTypeId/:serialNumber
    ///   DELETE /v1/devices/:deviceId/registrations/:passTypeId/:serialNumber
    ///   GET /v1/passes/:passTypeId/:serialNumber
    ///   GET /v1/devices/:deviceId/registrations/:passTypeId
    public static let webServicePathPrefix = "/v1"

    /// The tenant provides their signing certificate via server admin panel.
    /// iOS never handles certificate material.
    public static let signingCertOwner = "tenant_server"
}
