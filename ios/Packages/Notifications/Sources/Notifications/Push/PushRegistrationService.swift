import Foundation
import UserNotifications
import Core
import Networking

#if canImport(UIKit)
import UIKit
#endif

// MARK: - PushRegistrationService
//
// High-level facade over `PushRegistrar` + `UNUserNotificationCenter` permission flow.
// This is the *single wiring point* the app-shell must call — it encapsulates:
//   1. Permission request (deferred until after first login, per §21.1).
//   2. UIApplication remote-notification registration.
//   3. APNs token upload via POST /api/v1/devices/register.
//   4. Logout / unregistration.
//
// The app-shell wires this via `@UIApplicationDelegateAdaptor(NotificationsAppDelegate.self)`.
// See integration note at the bottom of this file.
//
// IMPORTANT — BizarreCRMApp.swift is advisory-locked. Do NOT import or reference
// it here. The app-shell owner calls `PushRegistrationService.shared` after login.

/// Public protocol so consumers (e.g. the app shell, tests) can substitute a mock.
public protocol PushRegistrationServiceProtocol: Sendable {
    /// Current registration state.
    var state: PushRegistrationState { get async }

    /// Full flow: request permission → register with system → upload token to server.
    /// Safe to call multiple times (idempotent if already registered).
    /// Throws if the system permission request throws.
    func registerIfAuthorized() async throws

    /// Remove the stored token from Keychain and notify the server.
    /// Call on successful logout.
    func unregisterOnLogout() async throws

    /// Expose stored token for diagnostic / refresh scenarios.
    var storedToken: String? { get async }
}

// MARK: - PushRegistrationService

/// Concrete implementation of `PushRegistrationServiceProtocol`.
///
/// ## App-shell integration (one-time wiring, BizarreCRMApp.swift owner's responsibility)
///
/// ```swift
/// // 1. Configure after successful login:
/// let service = PushRegistrationService.shared
/// await service.configure(api: apiClient, tenantId: session.tenantId)
/// try await service.registerIfAuthorized()
///
/// // 2. On logout:
/// try await PushRegistrationService.shared.unregisterOnLogout()
/// ```
///
/// `NotificationsAppDelegate` calls `PushRegistrar` directly for the
/// low-level APNs callbacks. `PushRegistrationService` is the higher-level
/// entry point that application code calls after authentication.
public actor PushRegistrationService: PushRegistrationServiceProtocol {

    // MARK: - Shared

    /// Shared singleton. The app shell calls `configure(api:tenantId:)` once
    /// after the user is authenticated.
    nonisolated(unsafe) public static var shared = PushRegistrationService()

    // MARK: - State

    /// Underlying registrar, set on `configure`.
    private var registrar: PushRegistrar?

    // MARK: - Init

    public init() {}

    // MARK: - Configuration

    /// Must be called once after login, before `registerIfAuthorized()`.
    /// Injects the authenticated `APIClient` and optional tenant ID.
    ///
    /// Also re-configures `NotificationsAppDelegate.shared` so APNs callbacks
    /// flow to the new registrar.
    public func configure(
        api: APIClient,
        tenantId: String? = nil
    ) {
        let r = PushRegistrar(api: api, tenantId: tenantId)
        self.registrar = r
        // Re-wire the app delegate with the fresh registrar.
        Task { @MainActor in
            NotificationsAppDelegate.shared.configure(
                registrar: r,
                silentPushHandler: SilentPushHandler.shared
            )
        }
    }

    // MARK: - PushRegistrationServiceProtocol

    public var state: PushRegistrationState {
        get async { await registrar?.state ?? .idle }
    }

    /// Request notification permission then call `registerForRemoteNotifications`.
    /// The OS later calls `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`,
    /// which invokes `PushRegistrar.receiveDeviceToken(_:)` → uploads to server.
    @discardableResult
    public func registerIfAuthorized() async throws -> UNAuthorizationStatus {
        guard let registrar else {
            AppLog.ui.error("PushRegistrationService: not configured — call configure(api:tenantId:) first")
            return .notDetermined
        }

        let status = try await registrar.requestAuthorization()
        guard status == .authorized || status == .provisional else {
            AppLog.ui.info("PushRegistrationService: permission status = \(String(describing: status), privacy: .public)")
            return status
        }
        await registrar.registerForRemoteNotifications()
        return status
    }

    public func unregisterOnLogout() async throws {
        guard let registrar else { return }
        try await registrar.unregisterDevice()
    }

    public var storedToken: String? {
        get async { await registrar?.storedToken }
    }

    // MARK: - Re-export permission check (convenience)

    /// Returns the current `UNAuthorizationStatus` without requesting permission.
    public func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
}

// MARK: - Integration note for BizarreCRMApp.swift owner
//
// Wire in `BizarreCRMApp.swift` (advisory-lock file, owner does the edit):
//
// ```swift
// @UIApplicationDelegateAdaptor(NotificationsAppDelegate.self)
// var notificationsAppDelegate
//
// // After successful login / session restore:
// func onLoginSuccess(api: APIClient, tenantId: String?) async {
//     await PushRegistrationService.shared.configure(api: api, tenantId: tenantId)
//     try? await PushRegistrationService.shared.registerIfAuthorized()
//
//     // Wire deep-link router BEFORE first push can arrive:
//     let coord = NotificationDeepLinkCoordinator(router: AppDeepLinkRouter.shared)
//     NotificationHandler.shared.configure(deepLinkRouter: coord)
// }
//
// // On logout:
// func onLogout() async {
//     try? await PushRegistrationService.shared.unregisterOnLogout()
// }
// ```
