import Foundation
#if canImport(EventKit)
import EventKit
#endif

// MARK: - CalendarAuthStatus

public enum CalendarAuthStatus: Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

// MARK: - CalendarPermissionHelper

/// Pure helper — requests EventKit calendar access and checks current status.
/// Wraps EKEventStore so call sites are not coupled to EventKit directly.
public enum CalendarPermissionHelper: Sendable {

    // MARK: - Public API

    /// Returns current authorization status without prompting.
    public static func currentStatus() -> CalendarAuthStatus {
        #if canImport(EventKit) && !os(macOS)
        if #available(iOS 17.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized, .fullAccess: return .authorized
            case .denied:                  return .denied
            case .restricted:              return .restricted
            case .notDetermined:           return .notDetermined
            case .writeOnly:               return .denied
            @unknown default:              return .notDetermined
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized: return .authorized
            case .denied:     return .denied
            case .restricted: return .restricted
            default:          return .notDetermined
            }
        }
        #else
        return .notDetermined
        #endif
    }

    /// Requests full calendar access (iOS 17+ uses `requestFullAccessToEvents`).
    /// Returns `true` if granted.
    @MainActor
    public static func requestAccess() async -> Bool {
        #if canImport(EventKit) && !os(macOS)
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            do {
                return try await store.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
        #else
        return false
        #endif
    }
}
