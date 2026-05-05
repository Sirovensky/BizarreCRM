import Foundation
import UserNotifications
import Core
import Networking

#if canImport(UIKit)
import UIKit
#endif

// MARK: - KeychainPushStore

/// Minimal keychain wrapper for the APNs device token.
/// Uses `kSecClassGenericPassword` directly — no third-party keychain library
/// needed for a single item (sovereignty rule §32).
public enum KeychainPushStore {
    private static let service = "com.bizarrecrm.push"
    private static let account = "deviceToken"

    /// Persist the hex device token string.
    public static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     account,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Load the persisted hex token string, or nil if absent.
    public static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     account,
            kSecReturnData:      true,
            kSecMatchLimit:      kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    /// Remove the stored token (called on logout).
    public static func delete() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - PushRegistrationState

/// State machine for the push registration lifecycle.
public enum PushRegistrationState: Sendable, Equatable {
    /// No action taken yet.
    case idle
    /// Waiting for the OS to issue a token after `registerForRemoteNotifications`.
    case pending
    /// Token received and uploaded to server.
    case registered(token: String)
    /// Authorization denied by user.
    case denied
    /// A network or server error occurred.
    case failed(String)
}

// MARK: - PushRegistrar

/// Manages the APNs device token lifecycle.
///
/// Usage (add to AppDelegate / BizarreCRMApp after successful auth):
/// ```swift
/// let registrar = PushRegistrar(api: api)
/// let status = try await registrar.requestAuthorization()
/// if status == .authorized {
///     await registrar.registerForRemoteNotifications()
/// }
/// // In AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken:
/// try await registrar.receiveDeviceToken(deviceTokenData)
/// // In AppDelegate.didFailToRegisterForRemoteNotificationsWithError:
/// await registrar.handleRegistrationFailure(error)
/// ```
///
/// **Entitlement note:**  `aps-environment` (development or production) MUST be present
/// in `ios/App/Resources/BizarreCRM.entitlements` before APNs tokens will be issued.
/// Add to the entitlements file:
/// ```xml
/// <key>aps-environment</key>
/// <string>development</string>   <!-- use "production" for App Store / TestFlight builds -->
/// ```
/// Personal-team builds cannot include this entitlement — it requires a paid Apple Developer
/// account. The user adds it when ready; do not check it in prematurely.
public actor PushRegistrar {

    // MARK: - Public state

    public private(set) var state: PushRegistrationState = .idle

    // MARK: - Private

    private let api: APIClient
    // Optional allows deferring .current() resolution to first use.
    // Tests inject a concrete non-nil value; production passes nil.
    private let _notificationCenter: UNUserNotificationCenter?
    private var notificationCenter: UNUserNotificationCenter {
        _notificationCenter ?? UNUserNotificationCenter.current()
    }
    private let tenantId: String?

    // MARK: - Init

    public init(
        api: APIClient,
        notificationCenter: UNUserNotificationCenter? = nil,
        tenantId: String? = nil
    ) {
        self.api = api
        self._notificationCenter = notificationCenter
        self.tenantId = tenantId
    }

    // MARK: - Authorization

    /// Requests notification authorization from the user and returns the
    /// resulting `UNAuthorizationStatus`.
    ///
    /// Call AFTER the user has logged in and understood what push is for —
    /// never on first launch (§21.1 deferred prompt rule).
    @discardableResult
    public func requestAuthorization() async throws -> UNAuthorizationStatus {
        do {
            try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            AppLog.ui.error("Push auth request failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let settings = await notificationCenter.notificationSettings()
        let status = settings.authorizationStatus
        if status == .denied { state = .denied }
        return status
    }

    // MARK: - System registration

    /// Calls `UIApplication.shared.registerForRemoteNotifications()`.
    /// Must run on the main actor; the actor hop is handled internally.
    public func registerForRemoteNotifications() async {
        state = .pending
#if canImport(UIKit)
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
#endif
    }

    // MARK: - Token receipt

    /// Called from `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Converts the raw `Data` to a hex string, persists to Keychain, then
    /// uploads to the server via `POST /api/v1/devices/register`.
    public func receiveDeviceToken(_ data: Data) async throws {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        KeychainPushStore.save(hex)

        let request = DeviceRegisterRequest(
            deviceToken: hex,
            deviceType: "ios",
            tenantId: tenantId,
            model: deviceModel(),
            iosVersion: iosVersionString(),
            appVersion: appVersionString(),
            locale: Locale.current.identifier
        )

        do {
            _ = try await api.registerDeviceToken(request)
            state = .registered(token: hex)
            AppLog.ui.info("APNs token registered: \(hex.prefix(8), privacy: .public)…")
        } catch {
            AppLog.ui.error("APNs token upload failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// §21.1 Token rotation — called when APNs issues a new token.
    /// Deletes the old token from the server, persists the new one, and re-registers.
    /// Safe to call every app launch — no-ops if the token has not changed.
    public func rotateDeviceTokenIfNeeded(_ data: Data) async throws {
        let newHex = data.map { String(format: "%02x", $0) }.joined()
        let existing = KeychainPushStore.load()

        // No-op when token hasn't changed.
        if existing == newHex {
            AppLog.ui.debug("APNs token rotation: token unchanged, skip")
            return
        }

        // Unregister old token from server (best-effort; old token naturally expires in 30d).
        if let old = existing {
            do {
                try await api.unregisterDeviceToken(old)
                AppLog.ui.info("APNs token rotation: old token removed from server")
            } catch {
                AppLog.ui.warning("APNs token rotation: failed to remove old token (non-fatal): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Register new token.
        try await receiveDeviceToken(data)
        AppLog.ui.info("APNs token rotation: new token registered \(newHex.prefix(8), privacy: .public)…")
    }

    /// Called from `AppDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    public func handleRegistrationFailure(_ error: Error) {
        state = .failed(error.localizedDescription)
        AppLog.ui.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Unregister

    /// Removes the stored token from Keychain and notifies the server.
    /// Call on logout so the server stops delivering pushes to this device.
    public func unregisterDevice() async throws {
        guard let token = KeychainPushStore.load() else {
            state = .idle
            return
        }
        do {
            try await api.unregisterDeviceToken(token)
        } catch {
            AppLog.ui.error("APNs unregister failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        KeychainPushStore.delete()
        state = .idle
    }

    // MARK: - Stored token accessor

    /// The hex token currently persisted in Keychain, or nil if not yet registered.
    public var storedToken: String? { KeychainPushStore.load() }

    // MARK: - Helpers

    private func deviceModel() -> String? {
#if canImport(UIKit)
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 1) {
                String(cString: UnsafePointer($0))
            }
        }
#else
        return nil
#endif
    }

    private func iosVersionString() -> String? {
#if canImport(UIKit)
        return UIDevice.current.systemVersion
#else
        return nil
#endif
    }

    private func appVersionString() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
