import AppIntents
import Foundation
#if os(iOS)

/// Cash drawer opener; delegates to an injected hardware interface.
public protocol CashDrawerInterface: Sendable {
    func open() async throws
}

enum CashDrawerRegistry: @unchecked Sendable {
    nonisolated(unsafe) static var drawer: CashDrawerInterface = UnavailableCashDrawer()
}

private struct UnavailableCashDrawer: CashDrawerInterface {
    func open() async throws {
        throw CashDrawerError.noDrawerRegistered
    }
}

public enum CashDrawerError: Error, LocalizedError {
    case noDrawerRegistered

    public var errorDescription: String? {
        "No cash drawer is connected."
    }
}

public enum NewCashDrawerIntentConfig {
    public static func register(_ drawer: CashDrawerInterface) {
        CashDrawerRegistry.drawer = drawer
    }
}

/// Opens the connected cash drawer.
@available(iOS 16, *)
public struct NewCashDrawerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Cash Drawer"
    public static let description = IntentDescription("Open the connected cash drawer.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await CashDrawerRegistry.drawer.open()
        return .result(dialog: IntentDialog("Cash drawer opened."))
    }
}
#endif // os(iOS)
