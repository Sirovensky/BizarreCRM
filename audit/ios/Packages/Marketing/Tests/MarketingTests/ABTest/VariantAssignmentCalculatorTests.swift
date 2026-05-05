import Testing
import Foundation
@testable import Marketing

@Suite("VariantAssignmentCalculator")
struct VariantAssignmentCalculatorTests {

    // MARK: - Fixtures

    private let fiftyFifty = ABTestVariant.fiftyFifty(messageA: "Hello A", messageB: "Hello B")
    private let sixtyForty = ABTestVariant.sixtyForty(messageA: "Hello A", messageB: "Hello B")

    // MARK: - Determinism

    @Test("same customerID always returns same variant")
    func sameIDReturnsSameVariant() {
        let first  = VariantAssignmentCalculator.assign(customerID: "cust-42", experimentID: "exp-1", variants: fiftyFifty)
        let second = VariantAssignmentCalculator.assign(customerID: "cust-42", experimentID: "exp-1", variants: fiftyFifty)
        #expect(first?.id == second?.id)
    }

    @Test("different customerIDs may return different variants")
    func differentIDsCanReturnDifferentVariants() {
        // Run across enough IDs to find at least one that differs.
        let ids = (0..<200).map { "cust-\($0)" }
        let labels = Set(ids.compactMap {
            VariantAssignmentCalculator.assign(customerID: $0, experimentID: "exp-dist", variants: fiftyFifty)?.label
        })
        #expect(labels.count == 2)
    }

    @Test("different experimentIDs produce different bucket distributions")
    func differentExperimentIDsDiffer() {
        // For the same customer, at least one of a large set of experiments should differ.
        let assignments1 = (0..<50).map {
            VariantAssignmentCalculator.assign(customerID: "cust-fixed", experimentID: "exp-\($0)", variants: fiftyFifty)?.splitPercent
        }
        let assignments2 = (0..<50).map {
            VariantAssignmentCalculator.assign(customerID: "cust-fixed", experimentID: "exp-x-\($0)", variants: fiftyFifty)?.splitPercent
        }
        // Arrays won't be identical (different experiment IDs change the hash input).
        #expect(assignments1 != assignments2)
    }

    // MARK: - Distribution accuracy

    @Test("50/50 split lands within ±8pp of 50% over 1000 assignments")
    func fiftyFiftyDistribution() {
        let ids = (0..<1000).map { "customer-\($0)" }
        let labelA = fiftyFifty[0].label
        let countA = ids.filter {
            VariantAssignmentCalculator.assign(customerID: $0, experimentID: "exp-50", variants: fiftyFifty)?.label == labelA
        }.count
        // Expect 42–58% in variant A (±8pp tolerance for deterministic hash)
        #expect(countA >= 420)
        #expect(countA <= 580)
    }

    @Test("60/40 split lands within ±8pp of 60% over 1000 assignments")
    func sixtyFortyDistribution() {
        let ids = (0..<1000).map { "customer-\($0)" }
        let labelA = sixtyForty[0].label
        let countA = ids.filter {
            VariantAssignmentCalculator.assign(customerID: $0, experimentID: "exp-60", variants: sixtyForty)?.label == labelA
        }.count
        // Expect 52–68% in variant A
        #expect(countA >= 520)
        #expect(countA <= 680)
    }

    @Test("three-way 33/33/34 split assigns all three variants over 1000 customers")
    func threeWayDistribution() {
        let threeWay = [
            ABTestVariant(label: "A", message: "msg A", splitPercent: 33),
            ABTestVariant(label: "B", message: "msg B", splitPercent: 33),
            ABTestVariant(label: "C", message: "msg C", splitPercent: 34),
        ]
        let ids = (0..<1000).map { "cust-3way-\($0)" }
        let labels = Set(ids.compactMap {
            VariantAssignmentCalculator.assign(customerID: $0, experimentID: "exp-3way", variants: threeWay)?.label
        })
        #expect(labels == Set(["A", "B", "C"]))
    }

    // MARK: - Invalid inputs

    @Test("invalid variants (bad sum) returns nil")
    func invalidVariantsReturnsNil() {
        let bad = [
            ABTestVariant(label: "A", message: "", splitPercent: 50),
            ABTestVariant(label: "B", message: "", splitPercent: 30), // sum = 80
        ]
        let result = VariantAssignmentCalculator.assign(customerID: "c1", experimentID: "e1", variants: bad)
        #expect(result == nil)
    }

    @Test("empty variant list returns nil")
    func emptyVariantListReturnsNil() {
        let result = VariantAssignmentCalculator.assign(customerID: "c1", experimentID: "e1", variants: [])
        #expect(result == nil)
    }

    @Test("single-variant list returns nil (invalid — fewer than 2)")
    func singleVariantReturnsNil() {
        let single = [ABTestVariant(label: "Only", message: "", splitPercent: 100)]
        let result = VariantAssignmentCalculator.assign(customerID: "c1", experimentID: "e1", variants: single)
        #expect(result == nil)
    }

    // MARK: - hashPercentile internals

    @Test("hashPercentile returns value in [0, 100)")
    func hashPercentileRange() {
        let ids = (0..<500).map { "hash-test-\($0)" }
        for id in ids {
            let p = VariantAssignmentCalculator.hashPercentile(customerID: id, experimentID: "exp-hash")
            #expect(p >= 0)
            #expect(p < 100)
        }
    }

    @Test("hashPercentile is deterministic for same inputs")
    func hashPercentileDeterministic() {
        let p1 = VariantAssignmentCalculator.hashPercentile(customerID: "abc", experimentID: "xyz")
        let p2 = VariantAssignmentCalculator.hashPercentile(customerID: "abc", experimentID: "xyz")
        #expect(p1 == p2)
    }

    @Test("hashPercentile differs for different customerIDs")
    func hashPercentileDiffersAcrossCustomers() {
        let percents = Set((0..<100).map {
            VariantAssignmentCalculator.hashPercentile(customerID: "customer-\($0)", experimentID: "exp-uniq")
        })
        // With 100 unique IDs, expect at least 70 distinct buckets (confirms spread)
        #expect(percents.count >= 70)
    }

    // MARK: - variant(atPercentile:in:)

    @Test("percentile 0 lands in first variant bucket")
    func percentileZeroLandsInFirst() {
        let variants = [
            ABTestVariant(label: "A", message: "", splitPercent: 50),
            ABTestVariant(label: "B", message: "", splitPercent: 50),
        ]
        let result = VariantAssignmentCalculator.variant(atPercentile: 0, in: variants)
        #expect(result?.label == "A")
    }

    @Test("percentile 49 lands in first variant of 50/50 split")
    func percentile49LandsInFirst() {
        let variants = [
            ABTestVariant(label: "A", message: "", splitPercent: 50),
            ABTestVariant(label: "B", message: "", splitPercent: 50),
        ]
        let result = VariantAssignmentCalculator.variant(atPercentile: 49, in: variants)
        #expect(result?.label == "A")
    }

    @Test("percentile 50 lands in second variant of 50/50 split")
    func percentile50LandsInSecond() {
        let variants = [
            ABTestVariant(label: "A", message: "", splitPercent: 50),
            ABTestVariant(label: "B", message: "", splitPercent: 50),
        ]
        let result = VariantAssignmentCalculator.variant(atPercentile: 50, in: variants)
        #expect(result?.label == "B")
    }

    @Test("percentile 99 lands in last variant")
    func percentile99LandsInLast() {
        let variants = [
            ABTestVariant(label: "A", message: "", splitPercent: 50),
            ABTestVariant(label: "B", message: "", splitPercent: 50),
        ]
        let result = VariantAssignmentCalculator.variant(atPercentile: 99, in: variants)
        #expect(result?.label == "B")
    }

    @Test("60/40 split: percentile 59 is in A, 60 is in B")
    func sixtyFortyBoundary() {
        let variants = [
            ABTestVariant(label: "A", message: "", splitPercent: 60),
            ABTestVariant(label: "B", message: "", splitPercent: 40),
        ]
        #expect(VariantAssignmentCalculator.variant(atPercentile: 59, in: variants)?.label == "A")
        #expect(VariantAssignmentCalculator.variant(atPercentile: 60, in: variants)?.label == "B")
    }
}
