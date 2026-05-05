import Foundation
import Observation

// MARK: - §60.1 LocationContext

/// Persists the active location across the process and into the App Group
/// so Home Screen widgets can read the same active location.
///
/// Responds to `.locationDidSwitch` posts — domain repositories observe
/// this notification and re-fetch scoped data.
@Observable
@MainActor
public final class LocationContext {

    // MARK: Notification name

    public static let locationDidSwitch = Notification.Name("com.bizarrecrm.locationDidSwitch")

    // MARK: Shared singleton

    public static let shared = LocationContext()

    // MARK: Persistence

    private static let suiteDefaults = UserDefaults(suiteName: "group.com.bizarrecrm")
    private static let persistenceKey = "activeLocationId"

    // MARK: Observable state

    /// The currently active location ID. Setting this value persists the
    /// change and posts `.locationDidSwitch` so domain repos can re-fetch.
    public private(set) var activeLocationId: String

    // MARK: Init

    public init(initialLocationId: String? = nil) {
        let stored = initialLocationId
            ?? Self.suiteDefaults?.string(forKey: Self.persistenceKey)
            ?? ""
        self.activeLocationId = stored
    }

    // MARK: Public API

    /// Switch the active location. Posts `.locationDidSwitch` on `NotificationCenter.default`
    /// with `userInfo["locationId"]` set to the new ID.
    public func `switch`(locationId: String) {
        guard locationId != activeLocationId else { return }
        activeLocationId = locationId
        Self.suiteDefaults?.set(locationId, forKey: Self.persistenceKey)
        NotificationCenter.default.post(
            name: Self.locationDidSwitch,
            object: self,
            userInfo: ["locationId": locationId]
        )
    }
}
