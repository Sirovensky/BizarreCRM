#if canImport(UIKit)
import Foundation
import Observation
import Networking

// MARK: - GiftCardIssueViewModel

/// §40 — State machine for `GiftCardIssueView`.
///
/// Issues a new gift card via `POST /api/v1/gift-cards`.
/// Only admin/manager roles may call this endpoint (enforced server-side;
/// the UI pre-validates so the button is disabled for cashiers, but the
/// server is authoritative).
///
/// Money in cents throughout. `IssueGiftCardRequest` handles cents → dollars
/// conversion at the network boundary.
///
/// State machine:
///   `.idle` → `.issuing` → `.issued(code:balanceCents:)`
///   `.idle` → `.issuing` → `.failure(String)`
@MainActor
@Observable
public final class GiftCardIssueViewModel {

    // MARK: - Constants

    /// Server cap: $10,000 per card.
    public static let maxAmountCents: Int = 1_000_000

    // MARK: - State

    public enum State: Equatable, Sendable {
        case idle
        case issuing
        case issued(code: String, balanceCents: Int)
        case failure(String)
    }

    // MARK: - Properties

    public private(set) var state: State = .idle

    /// Amount field — cashier enters cents as an integer string.
    public var amountInput: String = ""

    /// Optional: attach to a customer (id).
    public var customerId: Int64? = nil

    /// Optional recipient name (shown on the issued card confirmation).
    public var recipientName: String = ""

    /// Optional recipient email (server may send a notification).
    public var recipientEmail: String = ""

    /// Optional expiry date in ISO-8601 format (`yyyy-MM-dd`).
    public var expiresAtInput: String = ""

    /// Optional notes for the cashier / manager.
    public var notes: String = ""

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Computed

    public var amountCents: Int {
        Int(amountInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Returns a user-facing validation message or `nil` when the form is valid.
    public var validationError: String? {
        if amountCents <= 0 {
            return "Enter an amount greater than zero."
        }
        if amountCents > Self.maxAmountCents {
            return "Amount cannot exceed $\(Self.maxAmountCents / 100)."
        }
        let email = recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty && !isValidEmail(email) {
            return "Enter a valid email address."
        }
        return nil
    }

    public var canIssue: Bool {
        validationError == nil && state != .issuing
    }

    // MARK: - Actions

    /// `POST /api/v1/gift-cards` — create a new gift card.
    public func issue() async {
        guard canIssue else { return }
        state = .issuing

        let email = recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let name  = recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let exp   = expiresAtInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = IssueGiftCardRequest(
            amountCents: amountCents,
            customerId: customerId,
            recipientName: name.isEmpty ? nil : name,
            recipientEmail: email.isEmpty ? nil : email,
            expiresAt: exp.isEmpty ? nil : exp,
            notes: notesTrimmed.isEmpty ? nil : notesTrimmed
        )
        do {
            let response = try await api.issueGiftCard(request)
            state = .issued(code: response.code, balanceCents: amountCents)
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Issue failed"
            state = .failure("Issue failed (\(code)): \(msg)")
        } catch {
            state = .failure("Issue failed: \(error.localizedDescription)")
        }
    }

    public func reset() {
        state = .idle
        amountInput = ""
        customerId = nil
        recipientName = ""
        recipientEmail = ""
        expiresAtInput = ""
        notes = ""
    }

    // MARK: - Helpers

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".")
    }
}
#endif
