#if canImport(UIKit)
import Foundation
import Observation
import Networking

// MARK: - GiftCardReloadViewModel

/// State machine for `GiftCardReloadSheet`.
///
/// Validates the reload amount against three rules:
/// - `amount > 0`
/// - Card must be active
/// - Resulting balance must not exceed `maxBalanceCents` ($500 = 50000 cents)
///
/// Money in cents. Boundary conversion handled by `GiftCardsEndpoints`.
@MainActor
@Observable
public final class GiftCardReloadViewModel {

    // MARK: - Constants

    public static let maxBalanceCents: Int = 50_000 // $500.00

    // MARK: - State

    public enum State: Equatable, Sendable {
        case idle
        case loading
        case success(newBalanceCents: Int)
        case failure(String)
    }

    // MARK: - Properties

    public private(set) var state: State = .idle

    /// The card to reload (loaded from a prior lookup or passed in).
    public var card: GiftCard?

    /// Cents input string from the amount field.
    public var amountInput: String = ""

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Computed

    public var amountCents: Int {
        Int(amountInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Returns a user-facing validation error message or `nil` when valid.
    public var validationError: String? {
        guard let card else { return "No card selected." }
        guard card.active else { return "Card is not active." }
        guard amountCents > 0 else { return "Enter an amount greater than zero." }
        let newBalance = card.balanceCents + amountCents
        if newBalance > Self.maxBalanceCents {
            let remaining = Self.maxBalanceCents - card.balanceCents
            return "Maximum card balance is \(CartMath.formatCents(Self.maxBalanceCents)). You can add up to \(CartMath.formatCents(remaining))."
        }
        return nil
    }

    public var canReload: Bool {
        validationError == nil && state != .loading
    }

    // MARK: - Actions

    /// POST /gift-cards/:id/reload
    public func reload() async {
        guard let card, canReload else { return }
        state = .loading
        do {
            let response = try await api.reloadGiftCard(id: card.id, amountCents: amountCents)
            state = .success(newBalanceCents: response.newBalanceCents)
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Reload failed"
            state = .failure("Reload failed (\(code)): \(msg)")
        } catch {
            state = .failure("Reload failed: \(error.localizedDescription)")
        }
    }

    public func reset() {
        state = .idle
        amountInput = ""
    }
}
#endif
