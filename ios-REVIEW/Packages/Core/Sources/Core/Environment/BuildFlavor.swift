import Foundation

// §77 Environment & Build Flavor helpers
// Detects which flavor the binary was built for, using two signals:
//   1. CFBundleIdentifier suffix  (most reliable — set in xcconfig)
//   2. CFBundleName fallback       (set in Info.plist by write-info-plist.sh)
//
// Convention (matches what scripts/write-info-plist.sh is expected to emit):
//   production  → bundle ID "com.bizarrecrm"           name "BizarreCRM"
//   staging     → bundle ID "com.bizarrecrm.staging"   name "BizarreCRM Staging"
//   development → bundle ID "com.bizarrecrm.dev"       name "BizarreCRM Dev"
//
// For unit tests the bundle ID is the test-host's bundle, which falls through
// to `.development` — fine for test assertions.

/// The build flavor (environment tier) of the running binary.
public enum BuildFlavor: String, Equatable, CaseIterable, Sendable {
    case production
    case staging
    case development

    // MARK: - Detection

    /// The flavor detected from the host bundle.
    ///
    /// The result is computed once and cached — bundle metadata is immutable
    /// at runtime.
    public static let current: BuildFlavor = detect(from: Bundle.main)

    /// Detects the flavor from an arbitrary bundle (injectable for tests).
    static func detect(from bundle: BundleInfoProvider) -> BuildFlavor {
        if let bundleID = bundle.bundleIdentifier {
            if bundleID.hasSuffix(".staging") { return .staging }
            if bundleID.hasSuffix(".dev")     { return .development }
            if bundleID == "com.bizarrecrm"   { return .production }
        }
        // Fallback: CFBundleName
        if let name = bundle.bundleName {
            let lower = name.lowercased()
            if lower.contains("staging") { return .staging }
            if lower.contains("dev")     { return .development }
        }
        // Unknown bundles (e.g. SPM test runner) → development
        return .development
    }

    // MARK: - Convenience

    /// `true` only for `.production` builds.
    public var isProduction: Bool { self == .production }

    /// `true` for `.staging` and `.development` builds.
    public var isNonProduction: Bool { !isProduction }

    /// Short label suitable for UI banners and log messages.
    public var label: String {
        switch self {
        case .production:  return "PROD"
        case .staging:     return "STAGING"
        case .development: return "DEV"
        }
    }
}

// MARK: - BundleInfoProvider

/// Abstraction over `Bundle` so that `detect(from:)` is unit-testable
/// without touching the real bundle or using `Bundle.main`.
public protocol BundleInfoProvider: Sendable {
    var bundleIdentifier: String? { get }
    var bundleName: String? { get }
}

extension Bundle: BundleInfoProvider {
    public var bundleName: String? {
        infoDictionary?["CFBundleName"] as? String
    }
}
