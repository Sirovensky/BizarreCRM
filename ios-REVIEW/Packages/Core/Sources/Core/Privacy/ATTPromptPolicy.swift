import Foundation

// §28.13 / §32.5 — App Tracking Transparency (ATT) prompt policy
//
// BizarreCRM does NOT cross-app track users and does NOT use IDFA.
// Therefore we MUST NOT call ATTrackingManager.requestTrackingAuthorization().
// Apple's guidelines require requesting ATT only when the app actually accesses
// IDFA — requesting it gratuitously is a grounds for App Review rejection.
//
// This file codifies that decision so it is:
//   (a) discoverable to future engineers,
//   (b) surfaced as a UI string in Settings → Privacy (privacy nutrition label),
//   (c) assertable in tests.

// MARK: - ATTPromptPolicy

/// Encapsulates the project decision that BizarreCRM does not request ATT.
///
/// All cross-app identifiers (IDFA, third-party pixels) are forbidden (§32).
/// Analytics go to the tenant's own server, not ad networks. No ATT dialog
/// is presented — doing so would be a misleading permission request.
public enum ATTPromptPolicy {

    /// BizarreCRM never presents the ATT dialog.
    ///
    /// Set to `false` unconditionally. If this ever needs to change (e.g. a
    /// future feature genuinely requires IDFA), flip this flag AND update
    /// `PrivacyNutritionLabelData.notCollected`, the `PrivacyInfo.xcprivacy`
    /// `NSPrivacyTracking` key, and get a security-reviewer sign-off.
    public static let shouldRequestAuthorization: Bool = false

    // MARK: - Copy strings (used in PrivacyNutritionLabelView + ATT sheet if ever needed)

    /// Short display name shown in Settings → Privacy.
    public static let displayTitle: String = "App Tracking Transparency"

    /// One-line summary shown in the privacy nutrition label.
    public static let summary: String =
        "BizarreCRM does not track you across other apps or websites. No IDFA or ad-network identifiers are collected."

    /// Longer disclosure for privacy policy / App Store description.
    public static let fullDisclosure: String = """
        BizarreCRM uses Apple's App Tracking Transparency framework \
        by design: we never request authorization because we do not use the \
        Advertising Identifier (IDFA) or share data with third-party ad networks. \
        All analytics are sent exclusively to your business's own server \
        (see Settings → Privacy → Analytics).
        """

    // MARK: - Assertion

    /// Call once at app startup in DEBUG builds to assert the policy is respected.
    ///
    /// Usage: `ATTPromptPolicy.assertNotRequested()`
    public static func assertNotRequested() {
        #if DEBUG
        assert(
            !shouldRequestAuthorization,
            "ATT should never be requested — see ATTPromptPolicy documentation"
        )
        #endif
    }
}
