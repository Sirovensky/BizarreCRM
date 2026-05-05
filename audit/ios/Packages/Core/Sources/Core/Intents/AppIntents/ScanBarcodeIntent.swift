import AppIntents
#if os(iOS)
import UIKit
import Foundation

/// App Intent that launches the in-app barcode scanner. The scanner is opened
/// via deep link; the app shell handles the actual AVFoundation camera session.
@available(iOS 16, *)
public struct ScanBarcodeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Scan Barcode"
    public static let openAppWhenRun = true
    public static let description = IntentDescription(
        "Launch the barcode scanner to look up inventory or tickets."
    )

    /// Optional context hint forwarded to the scanner so the app shell can
    /// pre-configure the scanner's expected output (inventory vs ticket).
    @Parameter(title: "Context", description: "Optional context: 'inventory' or 'ticket'")
    public var context: String?

    public init() {}

    public init(context: String? = nil) {
        self.context = context
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        var components = URLComponents()
        components.scheme = "bizarrecrm"
        components.host = "scanner"
        components.path = "/barcode"

        if let ctx = context, !ctx.isEmpty {
            components.queryItems = [URLQueryItem(name: "context", value: ctx)]
        }

        if let url = components.url {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}
#endif // os(iOS)
