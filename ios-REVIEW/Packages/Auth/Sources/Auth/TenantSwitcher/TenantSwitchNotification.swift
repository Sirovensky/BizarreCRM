import Foundation

public extension Notification.Name {
    /// Posted by `TenantStore` after a successful tenant switch.
    ///
    /// `userInfo` key `"tenant"` carries the newly-active `Tenant` value.
    /// Host app should observe this to flush per-tenant caches and navigate
    /// back to the dashboard.
    ///
    /// Example:
    /// ```swift
    /// NotificationCenter.default.addObserver(
    ///     forName: .tenantDidSwitch, object: nil, queue: .main
    /// ) { note in
    ///     let tenant = note.userInfo?["tenant"] as? Tenant
    ///     await appServices.reconfigureForTenant(tenant!)
    /// }
    /// ```
    static let tenantDidSwitch = Notification.Name("com.bizarrecrm.tenant.didSwitch")
}
