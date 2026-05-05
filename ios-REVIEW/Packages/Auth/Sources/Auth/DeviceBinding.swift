import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - §2.13 Device binding

/// Ties stored credentials to a stable device class identifier.
///
/// **Threat model:** Prevents credential theft via backup export. If a user's
/// Keychain backup is restored to a different device class, the binding check
/// fails and the user must re-authenticate from scratch.
///
/// **Device class ID** is derived from `UIDevice.current.identifierForVendor`
/// combined with a hardware model string (both stable within a device lifecycle).
/// It is NOT the raw UDID — using the vendor identifier avoids UDID restrictions.
///
/// **Per-tenant scope:** Each tenant stores a separate binding so a user who
/// works at two shops keeps independent device bindings.
///
/// **Reinstall behaviour:** `identifierForVendor` resets on reinstall; this is
/// intentional — reinstall = re-auth required to rebind.
///
/// Usage:
/// ```swift
/// // On first successful login:
/// DeviceBinding.shared.bind(tenantId: tenant.id)
///
/// // On every subsequent app launch:
/// guard DeviceBinding.shared.isValid(tenantId: tenant.id) else {
///     // Device changed — force full re-auth, clear Keychain creds.
/// }
///
/// // On logout / revoke:
/// DeviceBinding.shared.clear(tenantId: tenant.id)
/// ```
public final class DeviceBinding: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = DeviceBinding()

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Stores the current device binding for `tenantId`.
    /// Call immediately after a successful first-time login on this device.
    public func bind(tenantId: String) {
        let key = storageKey(tenantId: tenantId)
        let deviceId = Self.currentDeviceClassId()
        UserDefaults.standard.set(deviceId, forKey: key)
    }

    /// Returns `true` when the stored binding matches the current device.
    ///
    /// Returns `true` if no binding has been stored yet — the caller must
    /// call `bind(tenantId:)` after the first successful login to establish it.
    public func isValid(tenantId: String) -> Bool {
        let key = storageKey(tenantId: tenantId)
        guard let stored = UserDefaults.standard.string(forKey: key) else {
            // No binding stored — pass through; bind after next successful login.
            return true
        }
        return stored == Self.currentDeviceClassId()
    }

    /// Removes the device binding for `tenantId`. Call on logout / revocation.
    public func clear(tenantId: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(tenantId: tenantId))
    }

    // MARK: - Private

    private func storageKey(tenantId: String) -> String {
        "com.bizarrecrm.auth.device_binding.\(tenantId)"
    }

    /// A stable opaque string representing this device's class.
    ///
    /// Composed of `UIDevice.identifierForVendor` + hardware model string.
    /// On the simulator (Xcode previews / CI) returns a static placeholder.
    static func currentDeviceClassId() -> String {
        #if canImport(UIKit)
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let model    = UIDevice.current.model
        return "\(vendorId).\(model)"
        #else
        return "macos.unknown"
        #endif
    }
}
