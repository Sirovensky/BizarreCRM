#if canImport(UIKit)
import Foundation
import Observation
import Networking

// MARK: - GiftCardSellViewModel

/// State machine for `GiftCardSellSheet`.
///
/// Supports two paths:
/// 1. **Physical** — cashier scans or types a barcode; we look up the card.
///    If the server returns `status == "unissued"` the cashier enters an
///    activation amount and we POST `/gift-cards/:id/activate`.
/// 2. **Virtual** — cashier fills recipient name, email, amount, optional
///    message; we POST `/gift-cards` and the server sends the email + QR.
///
/// State machine:
///   `.idle` → `.scanning` → `.activating` → `.sent`
///   `.idle`                              → `.sent`  (virtual path)
///
/// Money in cents throughout. The boundary conversion (cents → dollars) is
/// handled inside `GiftCardsEndpoints` — this VM never touches `Decimal`.
@MainActor
@Observable
public final class GiftCardSellViewModel {

    // MARK: - State machine

    public enum SellMode: Sendable {
        case physical
        case virtual
    }

    public enum State: Equatable, Sendable {
        case idle
        case scanning
        case activating
        case sent(GiftCard)
        case failure(String)
    }

    // MARK: - Properties

    public private(set) var state: State = .idle
    public var sellMode: SellMode = .physical

    // Physical path
    public var barcodeInput: String = ""
    public private(set) var scannedCard: GiftCard?
    public var activationAmountInput: String = ""

    // Virtual path
    public var recipientName: String = ""
    public var recipientEmail: String = ""
    public var virtualAmountInput: String = ""
    public var message: String = ""

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Computed

    /// True when the scanned card can be activated (status == "unissued").
    public var isUnissued: Bool {
        guard let card = scannedCard else { return false }
        return !card.active && card.balanceCents == 0
    }

    public var activationAmountCents: Int {
        Int(activationAmountInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    public var virtualAmountCents: Int {
        Int(virtualAmountInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    public var canActivate: Bool {
        isUnissued && activationAmountCents > 0 && state != .activating
    }

    public var canSendVirtual: Bool {
        !recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isValidEmail(recipientEmail)
            && virtualAmountCents > 0
            && state != .activating
    }

    // MARK: - Physical flow

    /// Look up the scanned/typed card code.
    public func lookupCard() async {
        let trimmed = barcodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .scanning
        do {
            let card = try await api.lookupGiftCard(code: trimmed)
            scannedCard = card
            state = .idle
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Not found"
            state = .failure("Lookup failed (\(code)): \(msg)")
        } catch {
            state = .failure("Lookup failed: \(error.localizedDescription)")
        }
    }

    /// Activate a physical unissued card.
    public func activateCard() async {
        guard let card = scannedCard, isUnissued else { return }
        let amount = activationAmountCents
        guard amount > 0 else { return }
        state = .activating
        do {
            let activated = try await api.activateGiftCard(id: card.id, amountCents: amount)
            state = .sent(activated)
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Activation failed"
            state = .failure("Activate failed (\(code)): \(msg)")
        } catch {
            state = .failure("Activate failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Virtual flow

    /// Create and send a virtual gift card.
    public func sendVirtualCard() async {
        guard canSendVirtual else { return }
        state = .activating // reuse "processing" state
        let request = CreateVirtualGiftCardRequest(
            recipientEmail: recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            recipientName: recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
            amountCents: virtualAmountCents,
            message: message.isEmpty ? nil : message
        )
        do {
            let card = try await api.createVirtualGiftCard(request)
            state = .sent(card)
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Request failed"
            state = .failure("Send failed (\(code)): \(msg)")
        } catch {
            state = .failure("Send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    public func reset() {
        state = .idle
        barcodeInput = ""
        scannedCard = nil
        activationAmountInput = ""
        recipientName = ""
        recipientEmail = ""
        virtualAmountInput = ""
        message = ""
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Simple structural check — server does full validation.
        return trimmed.contains("@") && trimmed.contains(".")
    }
}
#endif
