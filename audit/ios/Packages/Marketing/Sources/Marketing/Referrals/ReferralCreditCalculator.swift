import Foundation

/// Pure, stateless calculator for referral credits.
/// No I/O, no side effects — fully unit-testable.
public enum ReferralCreditCalculator {

    /// Compute sender + receiver credits for a completed sale under a given rule.
    ///
    /// - Returns `.zero` (both 0 cents) when `sale.amountCents < rule.minSaleCents`.
    public static func credit(onSale sale: Sale, rule: ReferralRule) -> ReferralCredit {
        guard sale.amountCents >= rule.minSaleCents else {
            return ReferralCredit(senderCents: 0, receiverCents: 0)
        }

        switch rule.type {
        case .flat:
            return ReferralCredit(
                senderCents: rule.senderCreditCents,
                receiverCents: rule.receiverCreditCents
            )

        case .percentage:
            // percentageBps: 100 bps = 1%. Both sender and receiver receive the same %.
            let creditCents = (sale.amountCents * rule.percentageBps) / 10_000
            return ReferralCredit(senderCents: creditCents, receiverCents: creditCents)
        }
    }
}
