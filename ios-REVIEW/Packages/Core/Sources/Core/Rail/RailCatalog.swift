import SwiftUI

// §22.G — Static catalog of the 8 primary rail destinations.

public enum RailCatalog {

    /// The canonical ordered list of primary rail items, filtered for the
    /// current `MessagingPreference`. When the user has flipped messaging
    /// to `.device` the SMS destination is hidden — Communications is
    /// disabled in that mode and the rail row would dead-end.
    public static var primary: [RailItem] {
        var items = primaryAll
        if MessagingPreference.mode == .device {
            items.removeAll { $0.destination == .sms }
        }
        return items
    }

    /// Order matches the iPad mockup rail (top → bottom): Dashboard,
    /// Tickets, Customers, POS, Inventory, SMS, Reports, Settings.
    private static let primaryAll: [RailItem] = [
        RailItem(
            id: "dashboard",
            title: "Dashboard",
            systemImage: "house",
            destination: .dashboard
        ),
        RailItem(
            id: "tickets",
            title: "Tickets",
            systemImage: "wrench.and.screwdriver",
            destination: .tickets
        ),
        RailItem(
            id: "customers",
            title: "Customers",
            systemImage: "person.2",
            destination: .customers
        ),
        RailItem(
            id: "pos",
            title: "Point of Sale",
            systemImage: "cart",
            destination: .pos
        ),
        RailItem(
            id: "inventory",
            title: "Inventory",
            systemImage: "shippingbox",
            destination: .inventory
        ),
        RailItem(
            id: "sms",
            title: "SMS",
            systemImage: "message",
            destination: .sms
        ),
        RailItem(
            id: "reports",
            title: "Reports",
            systemImage: "chart.bar",
            destination: .reports
        ),
        RailItem(
            id: "settings",
            title: "Settings",
            systemImage: "gear",
            destination: .settings
        ),
    ]
}
