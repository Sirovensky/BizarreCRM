import AppIntents
#if os(iOS)
import UIKit
import Foundation

/// App Intent that opens a specific repair ticket by its human-readable order ID
/// (e.g. "T-042"). Deep-links into the app's ticket detail screen.
@available(iOS 16, *)
public struct LookupTicketIntent: AppIntent {
    public static let title: LocalizedStringResource = "Look Up Ticket"
    public static let openAppWhenRun = true
    public static let description = IntentDescription(
        "Open a repair ticket by its order ID (e.g. T-042)."
    )

    @Parameter(title: "Order ID", description: "The ticket order ID, e.g. T-042")
    public var orderId: String

    public init() { self.orderId = "" }

    public init(orderId: String) {
        self.orderId = orderId
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let trimmed = orderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LookupTicketIntentError.emptyOrderId
        }

        var components = URLComponents()
        components.scheme = "bizarrecrm"
        components.host = "tickets"
        components.path = "/lookup"
        components.queryItems = [URLQueryItem(name: "orderId", value: trimmed)]

        if let url = components.url {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}

// MARK: - Errors

public enum LookupTicketIntentError: Error, LocalizedError {
    case emptyOrderId

    public var errorDescription: String? {
        switch self {
        case .emptyOrderId:
            return "Please provide a valid ticket order ID."
        }
    }
}
#endif // os(iOS)
