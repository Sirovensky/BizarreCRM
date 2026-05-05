import Foundation
import Observation
import Networking

#if canImport(PassKit)
import PassKit
#endif

// MARK: - LoyaltyWalletServicing

/// Protocol abstraction over `LoyaltyWalletService` for testability.
#if canImport(PassKit) && canImport(UIKit)
public protocol LoyaltyWalletServicing: Sendable {
    func fetchPass(customerId: String) async throws -> URL
    func addToWallet(from url: URL) async throws
    func refreshPass(passId: String) async throws -> URL
}

extension LoyaltyWalletService: LoyaltyWalletServicing {}
#endif

// MARK: - LoyaltyWalletViewModel

/// §38 — View-model for the loyalty Apple Wallet pass flow.
///
/// State machine:
///   .idle       — no action taken yet
///   .fetching   — downloading `.pkpass` from server
///   .ready(URL) — pass downloaded; ready to present
///   .addedToWallet — user tapped "Add" in `PKAddPassesViewController`
///   .failed     — any error (message is user-readable)
@MainActor
@Observable
public final class LoyaltyWalletViewModel {

    // MARK: - State

    public enum WalletState: Equatable, Sendable {
        case idle
        case fetching
        case ready(URL)
        case addedToWallet
        case failed(String)

        public static func == (lhs: WalletState, rhs: WalletState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):           return true
            case (.fetching, .fetching):   return true
            case (.ready(let a), .ready(let b)): return a == b
            case (.addedToWallet, .addedToWallet): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    public private(set) var state: WalletState = .idle

    /// `true` when the pass is already in the user's Wallet.
    public private(set) var isPassInWallet: Bool = false

    // MARK: - Dependencies

#if canImport(PassKit) && canImport(UIKit)
    private let service: any LoyaltyWalletServicing
#endif
    private let customerId: String

    // MARK: - Init

#if canImport(PassKit) && canImport(UIKit)
    public init(service: any LoyaltyWalletServicing, customerId: String) {
        self.service = service
        self.customerId = customerId
    }
#else
    public init(customerId: String) {
        self.customerId = customerId
    }
#endif

    // MARK: - Actions

    /// Fetch the pass from the server then present it.
    public func addToWallet() async {
        state = .fetching
#if canImport(PassKit) && canImport(UIKit)
        do {
            let url = try await service.fetchPass(customerId: customerId)
            state = .ready(url)
            try await service.addToWallet(from: url)
            state = .addedToWallet
            isPassInWallet = true
        } catch {
            state = .failed(error.localizedDescription)
        }
#else
        state = .failed("Apple Wallet is not supported on this platform.")
#endif
    }

    /// Re-download a refreshed pass from the server.
    public func refreshPass(passId: String) async {
        state = .fetching
#if canImport(PassKit) && canImport(UIKit)
        do {
            let url = try await service.refreshPass(passId: passId)
            state = .ready(url)
        } catch {
            state = .failed(error.localizedDescription)
        }
#else
        state = .failed("Apple Wallet is not supported on this platform.")
#endif
    }

    /// Check if the pass identified by `serialNumber` is already in Wallet.
    public func checkWalletStatus(passTypeIdentifier: String, serialNumber: String) {
#if canImport(PassKit) && canImport(UIKit)
        let library = PKPassLibrary()
        let existing = library.passes()
            .filter { $0.passTypeIdentifier == passTypeIdentifier }
        isPassInWallet = existing.contains { $0.serialNumber == serialNumber }
#endif
    }

    /// Reset to idle (e.g. on re-appear).
    public func reset() {
        state = .idle
    }
}
