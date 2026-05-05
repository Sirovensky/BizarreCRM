#if canImport(PassKit) && canImport(UIKit)
import Foundation

/// Protocol abstraction over `GiftCardWalletService` for testability.
///
/// Conformances:
/// - `GiftCardWalletService` — production actor (via extension below).
/// - `MockGiftCardWalletService` — in test target only.
public protocol GiftCardWalletServicing: Sendable {
    func fetchPass(giftCardId: String) async throws -> URL
    func addToWallet(from url: URL) async throws
    func refreshPass(passId: String) async throws -> URL
}

extension GiftCardWalletService: GiftCardWalletServicing {}
#endif
