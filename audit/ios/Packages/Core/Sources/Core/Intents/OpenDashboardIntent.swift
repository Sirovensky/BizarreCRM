import AppIntents
#if os(iOS)
import UIKit
import Foundation

/// Deep-links to the Dashboard screen.
@available(iOS 16, *)
public struct OpenDashboardIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Dashboard"
    public static let openAppWhenRun = true
    public static let description = IntentDescription("Open the main dashboard.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let url = URL(string: "bizarrecrm://dashboard") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}
#endif
