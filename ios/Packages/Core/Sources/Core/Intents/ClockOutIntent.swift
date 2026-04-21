import AppIntents
import Foundation
#if os(iOS)

/// Clocks the authenticated employee out via the API.
@available(iOS 16, *)
public struct ClockOutIntent: AppIntent {
    public static let title: LocalizedStringResource = "Clock Out"
    public static let description = IntentDescription("Clock out to end your shift.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ClockRepositoryRegistry.repo.clockOut()
        return .result(dialog: IntentDialog("You're clocked out. Great work today!"))
    }
}
#endif // os(iOS)
