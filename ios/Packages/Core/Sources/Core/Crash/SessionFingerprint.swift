import Foundation
#if canImport(UIKit)
import UIKit
#endif

// §32.5 Crash recovery pipeline — Session fingerprint
// Phase 11

/// Immutable snapshot of session context attached to every crash report.
///
/// Contains no PII: no user name, email, phone, or raw IDs.
/// `tenantSlug` is a business-level identifier (e.g. "acme-repairs"), not a user identifier.
/// `userRole` is a role label (e.g. "admin", "cashier"), never a user ID.
public struct SessionFingerprint: Codable, Sendable {

    /// Hardware model string (e.g. "iPhone16,2").
    public let device: String

    /// iOS version string (e.g. "17.4").
    public let iOSVersion: String

    /// Short marketing version (e.g. "1.0.0").
    public let appVersion: String

    /// Build number from CFBundleVersion (e.g. "42").
    public let appBuild: String

    /// Tenant slug from the authenticated session (no PII).
    public let tenantSlug: String

    /// Role of the authenticated user (no PII).
    public let userRole: String

    public init(
        device: String,
        iOSVersion: String,
        appVersion: String,
        appBuild: String,
        tenantSlug: String,
        userRole: String
    ) {
        self.device = device
        self.iOSVersion = iOSVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.tenantSlug = tenantSlug
        self.userRole = userRole
    }
}

extension SessionFingerprint {

    /// Build a fingerprint from the current process environment.
    /// Pass `tenantSlug` and `userRole` from the live session.
    public static func current(tenantSlug: String, userRole: String) -> SessionFingerprint {
        let device = {
            var sysinfo = utsname()
            uname(&sysinfo)
            return withUnsafeBytes(of: &sysinfo.machine) { ptr in
                let bytes = ptr.bindMemory(to: CChar.self)
                return String(cString: bytes.baseAddress!)
            }
        }()

        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        let iOSVersion: String
        #if os(iOS) || os(tvOS)
        iOSVersion = UIDevice.current.systemVersion
        #else
        iOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        return SessionFingerprint(
            device: device,
            iOSVersion: iOSVersion,
            appVersion: appVersion,
            appBuild: appBuild,
            tenantSlug: tenantSlug,
            userRole: userRole
        )
    }
}
