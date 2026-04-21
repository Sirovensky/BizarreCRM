import AppIntents
#if os(iOS)
import UIKit
import Foundation

/// Creates a new repair ticket, opening the app's New Ticket screen.
@available(iOS 16, *)
public struct NewTicketIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Ticket"
    public static let openAppWhenRun = true
    public static let description = IntentDescription("Create a new repair ticket.")

    @Parameter(title: "Customer") public var customerName: String?
    @Parameter(title: "Device") public var device: String?

    public init() {}

    public init(customerName: String? = nil, device: String? = nil) {
        self.customerName = customerName
        self.device = device
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        var components = URLComponents()
        components.scheme = "bizarrecrm"
        components.host = "tickets"
        components.path = "/new"
        var items: [URLQueryItem] = []
        if let name = customerName { items.append(URLQueryItem(name: "customerName", value: name)) }
        if let dev = device { items.append(URLQueryItem(name: "device", value: dev)) }
        if !items.isEmpty { components.queryItems = items }
        if let url = components.url {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}
#endif
