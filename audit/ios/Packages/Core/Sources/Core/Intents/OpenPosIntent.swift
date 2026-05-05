import AppIntents
#if os(iOS)
import UIKit
import Foundation

/// Deep-links to the POS screen.
@available(iOS 16, *)
public struct OpenPosIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open POS"
    public static let openAppWhenRun = true
    public static let description = IntentDescription("Open the Point of Sale screen.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let url = URL(string: "bizarrecrm://pos") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}
#endif
