import Testing
@testable import Marketing

@Suite("ReferralCreditCalculator")
struct ReferralCreditCalculatorTests {

    // MARK: - Flat rule

    @Test("flat rule grants fixed credits regardless of sale amount")
    func flatRule() {
        let rule = ReferralRule(type: .flat, senderCreditCents: 500, receiverCreditCents: 250, minSaleCents: 0, percentageBps: 0)
        let sale = Sale(amountCents: 10_000)
        let credits = ReferralCreditCalculator.credit(onSale: sale, rule: rule)
        #expect(credits.senderCents == 500)
        #expect(credits.receiverCents == 250)
    }

    @Test("flat rule below min sale returns zero credits")
    func flatRuleBelowMin() {
        let rule = ReferralRule(type: .flat, senderCreditCents: 500, receiverCreditCents: 250, minSaleCents: 5000, percentageBps: 0)
        let sale = Sale(amountCents: 4999)
        let credits = ReferralCreditCalculator.credit(onSale: sale, rule: rule)
        #expect(credits.senderCents == 0)
        #expect(credits.receiverCents == 0)
    }

    @Test("flat rule exactly at min sale threshold grants credits")
    func flatRuleAtThreshold() {
        let rule = ReferralRule(type: .flat, senderCreditCents: 1000, receiverCreditCents: 500, minSaleCents: 5000, percentageBps: 0)
        let sale = Sale(amountCents: 5000)
        let credits = ReferralCreditCalculator.credit(onSale: sale, rule: rule)
        #expect(credits.senderCents == 1000)
        #expect(credits.receiverCents == 500)
    }

    // MARK: - Percentage rule

    @Test("percentage rule is bps of sale amount")
    func percentageRule() {
        // 500 bps = 5%
        let rule = ReferralRule(type: .percentage, senderCreditCents: 0, receiverCreditCents: 0, minSaleCents: 0, percentageBps: 500)
        let sale = Sale(amountCents: 10_000) // $100 → 5% = $5 = 500 cents
        let credits = ReferralCreditCalculator.credit(onSale: sale, rule: rule)
        #expect(credits.senderCents == 500)
        #expect(credits.receiverCents == 500)
    }

    @Test("percentage rule below min sale returns zero")
    func percentageRuleBelowMin() {
        let rule = ReferralRule(type: .percentage, senderCreditCents: 0, receiverCreditCents: 0, minSaleCents: 2000, percentageBps: 1000)
        let sale = Sale(amountCents: 1999)
        let credits = ReferralCreditCalculator.credit(onSale: sale, rule: rule)
        #expect(credits.senderCents == 0)
        #expect(credits.receiverCents == 0)
    }

    @Test("percentage of zero sale is zero")
    func percentageOfZero() {
        let rule = ReferralRule(type: .percentage, senderCreditCents: 0, receiverCreditCents: 0, minSaleCents: 0, percentageBps: 1000)
        let sale = Sale(amountCents: 0)
        let credits = ReferralCreditCalculator.credit(onSale: sale, rule: rule)
        #expect(credits.senderCents == 0)
        #expect(credits.receiverCents == 0)
    }

    // MARK: - Credit struct

    @Test("credit struct exposes totalCents")
    func totalCents() {
        let credit = ReferralCredit(senderCents: 300, receiverCents: 200)
        #expect(credit.totalCents == 500)
    }

    @Test("zero rule returns zero credits")
    func zeroRule() {
        let rule = ReferralRule(type: .flat, senderCreditCents: 0, receiverCreditCents: 0, minSaleCents: 0, percentageBps: 0)
        let sale = Sale(amountCents: 50_000)
        let credits = ReferralCreditCalculator.credit(onSale: sale, rule: rule)
        #expect(credits.senderCents == 0)
        #expect(credits.receiverCents == 0)
        #expect(credits.totalCents == 0)
    }
}
