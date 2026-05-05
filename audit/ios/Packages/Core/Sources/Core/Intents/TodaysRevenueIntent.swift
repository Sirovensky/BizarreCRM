import AppIntents
import Foundation
#if os(iOS)

/// Repository protocol for revenue data; injected at app launch.
public protocol RevenueRepository: Sendable {
    /// Returns today's revenue in cents.
    func todaysRevenueCents() async throws -> Int
}

enum RevenueRepositoryRegistry: @unchecked Sendable {
    nonisolated(unsafe) static var repo: RevenueRepository = EmptyRevenueRepository()
}

private struct EmptyRevenueRepository: RevenueRepository {
    func todaysRevenueCents() async throws -> Int { 0 }
}

public enum TodaysRevenueIntentConfig {
    public static func register(_ repo: RevenueRepository) {
        RevenueRepositoryRegistry.repo = repo
    }
}

/// Reads today's revenue and speaks it in Siri.
@available(iOS 16, *)
public struct TodaysRevenueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Today's Revenue"
    public static let description = IntentDescription("Speak today's total revenue.")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let cents = try await RevenueRepositoryRegistry.repo.todaysRevenueCents()
        let dollars = Double(cents) / 100.0
        let formatted = Self.currencyFormatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
        return .result(
            value: dollars,
            dialog: IntentDialog("Today's revenue is \(formatted).")
        )
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()
}
#endif // os(iOS)
