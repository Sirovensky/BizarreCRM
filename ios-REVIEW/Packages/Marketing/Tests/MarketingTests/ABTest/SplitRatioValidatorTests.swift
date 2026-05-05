import Testing
@testable import Marketing

@Suite("SplitRatioValidator")
struct SplitRatioValidatorTests {

    // MARK: - Helpers

    private func makeVariants(_ percents: [Int]) -> [ABTestVariant] {
        percents.enumerated().map { index, pct in
            ABTestVariant(label: "Variant \(index + 1)", message: "msg", splitPercent: pct)
        }
    }

    // MARK: - Valid cases

    @Test("50/50 split is valid")
    func fiftyFiftyIsValid() {
        let variants = makeVariants([50, 50])
        #expect(SplitRatioValidator.isValid(variants))
        #expect(SplitRatioValidator.validate(variants) == nil)
    }

    @Test("60/40 split is valid")
    func sixtyFortyIsValid() {
        let variants = makeVariants([60, 40])
        #expect(SplitRatioValidator.isValid(variants))
    }

    @Test("three-way 33/33/34 split is valid")
    func threeWaySplitIsValid() {
        let variants = makeVariants([33, 33, 34])
        #expect(SplitRatioValidator.isValid(variants))
    }

    @Test("1/99 edge split is valid")
    func oneNinetyNineIsValid() {
        let variants = makeVariants([1, 99])
        #expect(SplitRatioValidator.isValid(variants))
    }

    // MARK: - Too few variants

    @Test("empty array fails with tooFewVariants(0)")
    func emptyArrayFails() {
        let error = SplitRatioValidator.validate([])
        #expect(error == .tooFewVariants(count: 0))
    }

    @Test("single variant fails with tooFewVariants(1)")
    func singleVariantFails() {
        let variants = makeVariants([100])
        let error = SplitRatioValidator.validate(variants)
        #expect(error == .tooFewVariants(count: 1))
    }

    // MARK: - Out of range

    @Test("0% split percent fails")
    func zeroPercentFails() {
        let variants = makeVariants([0, 100])
        if case .percentOutOfRange(let label, let value) = SplitRatioValidator.validate(variants) {
            #expect(label == "Variant 1")
            #expect(value == 0)
        } else {
            Issue.record("Expected percentOutOfRange error")
        }
    }

    @Test("100% split percent fails")
    func hundredPercentFails() {
        let variants = [
            ABTestVariant(label: "A", message: "", splitPercent: 100),
            ABTestVariant(label: "B", message: "", splitPercent: 0),
        ]
        // The 100% variant hits the range check first
        guard let error = SplitRatioValidator.validate(variants) else {
            Issue.record("Expected an error")
            return
        }
        switch error {
        case .percentOutOfRange(let label, _):
            #expect(label == "A")
        default:
            // 0 for B also fires, either way it's a range error
            break
        }
    }

    // MARK: - Sum not 100

    @Test("50/49 summing to 99 fails")
    func sumNinetyNineFails() {
        let variants = makeVariants([50, 49])
        if case .sumNotOneHundred(let actual) = SplitRatioValidator.validate(variants) {
            #expect(actual == 99)
        } else {
            Issue.record("Expected sumNotOneHundred error")
        }
    }

    @Test("50/51 summing to 101 fails")
    func sumOneHundredOneFails() {
        let variants = makeVariants([50, 51])
        if case .sumNotOneHundred(let actual) = SplitRatioValidator.validate(variants) {
            #expect(actual == 101)
        } else {
            Issue.record("Expected sumNotOneHundred error")
        }
    }

    // MARK: - total() helper

    @Test("total() returns sum of all split percents")
    func totalReturnsSum() {
        let variants = makeVariants([40, 30, 30])
        #expect(SplitRatioValidator.total(variants) == 100)
    }

    @Test("total() of empty array is 0")
    func totalEmptyIsZero() {
        #expect(SplitRatioValidator.total([]) == 0)
    }

    // MARK: - Error localizedDescription

    @Test("tooFewVariants error has non-empty description")
    func tooFewVariantsDescription() {
        let error = SplitRatioValidator.ValidationError.tooFewVariants(count: 1)
        #expect((error.errorDescription ?? "").contains("1"))
    }

    @Test("percentOutOfRange error mentions label and value")
    func percentOutOfRangeDescription() {
        let error = SplitRatioValidator.ValidationError.percentOutOfRange(label: "Control", value: 0)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Control"))
        #expect(desc.contains("0"))
    }

    @Test("sumNotOneHundred error mentions actual total")
    func sumNotOneHundredDescription() {
        let error = SplitRatioValidator.ValidationError.sumNotOneHundred(actual: 97)
        #expect((error.errorDescription ?? "").contains("97"))
    }
}
