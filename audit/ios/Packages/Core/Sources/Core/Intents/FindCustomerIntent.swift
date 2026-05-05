import AppIntents
import Foundation
#if os(iOS)

/// Searches customers by name or phone; returns matching entities for multi-step Shortcuts chains.
@available(iOS 16, *)
public struct FindCustomerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Customer"
    public static let description = IntentDescription("Find customers by name or phone number.")

    @Parameter(title: "Search by") public var query: String

    public init() { self.query = "" }

    public init(query: String) {
        self.query = query
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[CustomerEntity]> {
        let results = try await CustomerEntityQueryRegistry.repo.customers(matching: query)
        return .result(value: results)
    }
}
#endif // os(iOS)
