import Testing
@testable import Marketing

@Suite("EstimatedCostCalculator")
struct EstimatedCostCalculatorTests {

    @Test("cost is recipients × $0.025")
    func costIsCorrect() {
        #expect(EstimatedCostCalculator.cost(recipients: 0) == 0.0)
        #expect(EstimatedCostCalculator.cost(recipients: 1) == 0.025)
        #expect(EstimatedCostCalculator.cost(recipients: 100) == 2.5)
        #expect(EstimatedCostCalculator.cost(recipients: 342) == 342 * 0.025)
    }

    @Test("formattedCost starts with ~$")
    func formattedCostPrefix() {
        let result = EstimatedCostCalculator.formattedCost(recipients: 10)
        #expect(result.hasPrefix("~"))
        #expect(result.contains("$"))
    }

    @Test("requiresApproval threshold is > 100")
    func approvalThreshold() {
        #expect(EstimatedCostCalculator.requiresApproval(recipients: 100) == false)
        #expect(EstimatedCostCalculator.requiresApproval(recipients: 101) == true)
        #expect(EstimatedCostCalculator.requiresApproval(recipients: 0) == false)
        #expect(EstimatedCostCalculator.requiresApproval(recipients: 1000) == true)
    }

    @Test("pricePerRecipient constant is $0.025")
    func priceConstant() {
        #expect(EstimatedCostCalculator.pricePerRecipient == 0.025)
    }

    @Test("formattedCost zero recipients shows ~$0")
    func zeroRecipients() {
        let result = EstimatedCostCalculator.formattedCost(recipients: 0)
        #expect(result.contains("0"))
    }
}
