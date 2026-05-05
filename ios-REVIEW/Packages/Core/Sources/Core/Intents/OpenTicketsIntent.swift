import AppIntents
#if os(iOS)
import UIKit
import Foundation

/// Deep-links to the Tickets list screen.
@available(iOS 16, *)
public struct OpenTicketsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Tickets"
    public static let openAppWhenRun = true
    public static let description = IntentDescription("Open the repair tickets list.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let url = URL(string: "bizarrecrm://tickets") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}
#endif
