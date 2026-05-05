import AppIntents
#if os(iOS)
import UIKit
import Foundation

/// App Intent that creates a new repair ticket, pre-filling customer and device
/// parameters when provided. Opens the app's New Ticket screen via deep link.
///
/// Requires both `CustomerEntity` and a device string so Shortcuts can chain
/// a customer-lookup before this intent.
@available(iOS 16, *)
public struct CreateTicketIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Ticket"
    public static let openAppWhenRun = true
    public static let description = IntentDescription(
        "Create a new repair ticket for a customer and device."
    )

    @Parameter(title: "Customer")
    public var customer: CustomerEntity?

    @Parameter(title: "Device", description: "Device make and model, e.g. iPhone 15 Pro")
    public var device: String?

    public init() {}

    public init(customer: CustomerEntity? = nil, device: String? = nil) {
        self.customer = customer
        self.device = device
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        var components = URLComponents()
        components.scheme = "bizarrecrm"
        components.host = "tickets"
        components.path = "/new"

        var items: [URLQueryItem] = []
        if let c = customer {
            items.append(URLQueryItem(name: "customerId", value: String(c.numericId)))
            items.append(URLQueryItem(name: "customerName", value: c.displayName))
        }
        if let d = device, !d.isEmpty {
            items.append(URLQueryItem(name: "device", value: d))
        }
        if !items.isEmpty { components.queryItems = items }

        if let url = components.url {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}
#endif // os(iOS)
