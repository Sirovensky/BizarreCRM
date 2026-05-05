#if canImport(UIKit)
import Foundation
import Observation
import Networking

/// Extracted view-model for `PosGiftCardSheet` — keeps the `View` body
/// under 200 lines and lets us unit-test the apply-amount clamping
/// without a UI test harness. The VM never holds a reference to `Cart`;
/// redeem takes the cart as a parameter so the call site always passes
/// the currently-active cart (Cart is a reference type but we stay
/// deliberately explicit rather than risk a retain-cycle on the view).
@MainActor
@Observable
final class PosGiftCardSheetViewModel {
    private let api: APIClient
    private(set) var remainingCents: Int
    private(set) var customerId: Int64?

    var codeInput: String = ""
    var applyCentsInput: String = ""

    private(set) var card: GiftCard?
    private(set) var isLookingUp: Bool = false
    private(set) var isRedeeming: Bool = false

    /// §16.6 — "Check balance only" result: populated by `checkBalanceOnly(card:)`,
    /// cleared by `dismissBalanceCheck()` or the next `lookup()`. Lets cashier
    /// show the customer remaining balance without committing the card to a tender.
    private(set) var balanceCheckResult: GiftCard? = nil

    private(set) var storeCredit: StoreCreditBalance?
    private(set) var isLoadingStoreCredit: Bool = false

    var errorMessage: String?

    init(api: APIClient, remainingCents: Int, customerId: Int64?) {
        self.api = api
        self.remainingCents = remainingCents
        self.customerId = customerId
    }

    /// Store-credit section renders only for an attached customer with a
    /// real server id (walk-ins have `id == nil`).
    var storeCreditSectionEnabled: Bool { customerId != nil }

    func remainingChanged(to new: Int) {
        remainingCents = new
        if let card = card, let parsed = Int(applyCentsInput) {
            let ceiling = defaultApplyCents(for: card)
            if parsed > ceiling {
                applyCentsInput = String(ceiling)
            }
        }
    }

    func defaultApplyCents(for card: GiftCard) -> Int {
        min(remainingCents, card.balanceCents)
    }

    /// Current parsed value, clamped to `[0, defaultApplyCents]`.
    func parsedApplyCents(for card: GiftCard) -> Int {
        let raw = Int(applyCentsInput) ?? defaultApplyCents(for: card)
        return max(0, min(defaultApplyCents(for: card), raw))
    }

    func canRedeem(card: GiftCard) -> Bool {
        !isRedeeming
            && remainingCents > 0
            && card.balanceCents > 0
            && parsedApplyCents(for: card) > 0
    }

    // MARK: - Lookup / Redeem

    func lookup() async {
        let trimmed = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        balanceCheckResult = nil  // clear stale balance-check on re-lookup
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let card = try await api.lookupGiftCard(code: trimmed)
            self.card = card
            self.applyCentsInput = String(defaultApplyCents(for: card))
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Not found"
            errorMessage = "Gift card lookup failed (\(code)): \(msg)"
        } catch {
            errorMessage = "Gift card lookup failed: \(error.localizedDescription)"
        }
    }

    /// §16.6 — Show the card's current balance without applying it to the cart.
    /// Populates `balanceCheckResult` which the view displays as an info pill.
    /// The card model from lookup is already the live balance; this just surfaces
    /// it explicitly so the cashier can read it aloud to the customer.
    func checkBalanceOnly(card: GiftCard) {
        balanceCheckResult = card
    }

    /// Dismiss the balance-check info pill.
    func dismissBalanceCheck() {
        balanceCheckResult = nil
    }

    /// Redeem against the loaded card. On success append an
    /// `AppliedTender` to `cart`. Sheet stays open so the cashier can
    /// add another card if the first didn't cover the total.
    func redeem(intoCart cart: Cart) async {
        guard let card = card else { return }
        let amount = parsedApplyCents(for: card)
        guard amount > 0 else { return }
        errorMessage = nil
        isRedeeming = true
        defer { isRedeeming = false }
        do {
            let result = try await api.redeemGiftCard(
                id: card.id,
                amountCents: amount,
                reason: "POS checkout"
            )
            let tender = AppliedTender(
                kind: .giftCard,
                amountCents: amount,
                label: AppliedTender.giftCardLabel(code: card.code),
                reference: String(card.id)
            )
            cart.apply(tender: tender)
            let remaining = result.remainingBalanceCents
            if remaining == 0 {
                codeInput = ""
                applyCentsInput = ""
                self.card = nil
            } else {
                self.card = GiftCard(
                    id: card.id,
                    code: card.code,
                    balanceCents: remaining,
                    currency: card.currency,
                    expiresAt: card.expiresAt,
                    active: card.active
                )
                applyCentsInput = String(defaultApplyCents(for: self.card!))
            }
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Request failed"
            errorMessage = "Redeem failed (\(code)): \(msg)"
        } catch {
            errorMessage = "Redeem failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Store credit

    func loadStoreCreditIfNeeded() async {
        guard let customerId, storeCredit == nil else { return }
        isLoadingStoreCredit = true
        defer { isLoadingStoreCredit = false }
        do {
            let balance = try await api.getStoreCreditBalance(customerId: customerId)
            self.storeCredit = balance
        } catch {
            // Silent — store credit is a nice-to-have; the gift-card flow
            // is the primary job of this sheet.
        }
    }

    func applicableStoreCreditCents() -> Int {
        guard let credit = storeCredit else { return 0 }
        return min(remainingCents, credit.balanceCents)
    }

    /// Mint an `AppliedTender` for the current store-credit balance. We
    /// do NOT hit the server here — the store-credit "use" POST fires at
    /// final charge time alongside the payment rail so tender rows and
    /// payment rows land in a single transaction.
    func applyStoreCredit() -> AppliedTender? {
        guard let credit = storeCredit else { return nil }
        let amount = applicableStoreCreditCents()
        guard amount > 0 else { return nil }
        return AppliedTender(
            kind: .storeCredit,
            amountCents: amount,
            label: "Store credit",
            reference: String(credit.customerId)
        )
    }

    /// Format the server's ISO-ish timestamp ("YYYY-MM-DD HH:MM:SS") as a
    /// short date. Fallback to the raw string when parsing fails.
    static func formattedExpiry(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return dateOnly.string(from: d) }
        let sql = DateFormatter()
        sql.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sql.locale = Locale(identifier: "en_US_POSIX")
        sql.timeZone = TimeZone(secondsFromGMT: 0)
        if let d = sql.date(from: raw) { return dateOnly.string(from: d) }
        return raw
    }

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
#endif
