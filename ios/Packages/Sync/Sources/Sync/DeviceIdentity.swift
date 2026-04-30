import Foundation
#if canImport(UIKit)
import UIKit
#endif

// §20.10 — Per-device-id on mutations
//
// Stable identifier attached to every `SyncOp` so the server can echo WS
// events back tagged with their originating device. This lets multi-device
// users (iPhone + iPad) ignore their own echoes and only apply remote
// updates from *other* devices, avoiding the round-trip duplicate-update
// flicker.
//
// The identifier is:
//   1. Read from / written to UserDefaults under `bizarre.deviceIdentity`.
//   2. Seeded with `UIDevice.identifierForVendor` on first launch.
//   3. Falls back to a freshly generated `UUID` when IDFV is unavailable
//      (Mac Catalyst paths, Designed-for-iPad on Mac without entitlement).
//
// IDFV resets on full uninstall, which is fine — the server just registers
// the new ID against the same user / tenant on next bootstrap.

public final class DeviceIdentity: @unchecked Sendable {

    public static let shared = DeviceIdentity()

    private static let storageKey = "bizarre.deviceIdentity"

    private let lock = NSLock()
    private var cached: String?

    private init() {}

    // MARK: - Public

    /// Stable device ID for this install. Cheap; safe to call from hot paths.
    public var deviceId: String {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }

        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Self.storageKey), !stored.isEmpty {
            cached = stored
            return stored
        }

        let fresh = Self.seedIdentifier()
        defaults.set(fresh, forKey: Self.storageKey)
        cached = fresh
        return fresh
    }

    /// Wipe + regenerate. Only call on tenant switch / explicit user reset.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        cached = nil
    }

    // MARK: - Internal

    private static func seedIdentifier() -> String {
        #if canImport(UIKit)
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        }
        #endif
        return UUID().uuidString
    }
}
