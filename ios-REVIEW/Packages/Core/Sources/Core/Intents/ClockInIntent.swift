import AppIntents
import Foundation
#if os(iOS)

/// Clock repository protocol for employee clock actions; injected at app launch.
public protocol ClockRepository: Sendable {
    func clockIn() async throws
    func clockOut() async throws
}

enum ClockRepositoryRegistry: @unchecked Sendable {
    nonisolated(unsafe) static var repo: ClockRepository = UnauthenticatedClockRepository()
}

private struct UnauthenticatedClockRepository: ClockRepository {
    func clockIn() async throws {
        throw AppIntentError.notAuthenticated
    }
    func clockOut() async throws {
        throw AppIntentError.notAuthenticated
    }
}

public enum ClockIntentConfig {
    public static func register(_ repo: ClockRepository) {
        ClockRepositoryRegistry.repo = repo
    }
}

public enum AppIntentError: Error, LocalizedError {
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        }
    }
}

/// Clocks the authenticated employee in via the API.
@available(iOS 16, *)
public struct ClockInIntent: AppIntent {
    public static let title: LocalizedStringResource = "Clock In"
    public static let description = IntentDescription("Clock in to start your shift.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ClockRepositoryRegistry.repo.clockIn()
        return .result(dialog: IntentDialog("You're clocked in. Good luck today!"))
    }
}
#endif // os(iOS)
