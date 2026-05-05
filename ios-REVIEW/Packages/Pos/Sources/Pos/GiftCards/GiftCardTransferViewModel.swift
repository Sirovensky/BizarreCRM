#if canImport(UIKit)
import Foundation
import Observation
import Networking

// MARK: - GiftCardTransferViewModel

/// State machine for `GiftCardTransferSheet`.
///
/// Transfers balance from one card to another. Both source and target codes
/// can be entered manually or via barcode scan (the sheet triggers
/// `lookupSource()` / `lookupTarget()` respectively). The transfer amount
/// is validated against the source card's current balance.
///
/// The audit entry is created server-side; no local audit work needed here.
@MainActor
@Observable
public final class GiftCardTransferViewModel {

    // MARK: - State

    public enum State: Equatable, Sendable {
        case idle
        case lookingUpSource
        case lookingUpTarget
        case transferring
        case success(TransferGiftCardResponse)
        case failure(String)
    }

    // MARK: - Properties

    public private(set) var state: State = .idle

    public var sourceCodeInput: String = ""
    public var targetCodeInput: String = ""
    public var amountInput: String = ""

    public private(set) var sourceCard: GiftCard?
    public private(set) var targetCard: GiftCard?

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Computed

    public var amountCents: Int {
        Int(amountInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// User-facing validation message, or `nil` when inputs are valid.
    public var validationError: String? {
        guard let source = sourceCard else { return "Look up the source card first." }
        guard targetCard != nil else { return "Look up the target card first." }
        guard source.active else { return "Source card is not active." }
        guard amountCents > 0 else { return "Enter an amount greater than zero." }
        guard amountCents <= source.balanceCents else {
            return "Amount exceeds source balance of \(CartMath.formatCents(source.balanceCents))."
        }
        return nil
    }

    public var canTransfer: Bool {
        validationError == nil && state != .transferring
    }

    // MARK: - Lookup

    public func lookupSource() async {
        let trimmed = sourceCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .lookingUpSource
        do {
            sourceCard = try await api.lookupGiftCard(code: trimmed)
            state = .idle
        } catch let APITransportError.httpStatus(code, message) {
            state = .failure("Source lookup failed (\(code)): \(message ?? "Not found")")
        } catch {
            state = .failure("Source lookup failed: \(error.localizedDescription)")
        }
    }

    public func lookupTarget() async {
        let trimmed = targetCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .lookingUpTarget
        do {
            targetCard = try await api.lookupGiftCard(code: trimmed)
            state = .idle
        } catch let APITransportError.httpStatus(code, message) {
            state = .failure("Target lookup failed (\(code)): \(message ?? "Not found")")
        } catch {
            state = .failure("Target lookup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Transfer

    public func transfer() async {
        guard let source = sourceCard, let target = targetCard, canTransfer else { return }
        state = .transferring
        let request = TransferGiftCardRequest(
            sourceCardId: source.id,
            targetCardId: target.id,
            amountCents: amountCents
        )
        do {
            let response = try await api.transferGiftCard(request)
            state = .success(response)
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Transfer failed"
            state = .failure("Transfer failed (\(code)): \(msg)")
        } catch {
            state = .failure("Transfer failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reset

    public func reset() {
        state = .idle
        sourceCodeInput = ""
        targetCodeInput = ""
        amountInput = ""
        sourceCard = nil
        targetCard = nil
    }
}
#endif
