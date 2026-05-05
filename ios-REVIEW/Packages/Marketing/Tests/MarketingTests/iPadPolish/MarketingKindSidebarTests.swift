import Testing
import Foundation
@testable import Marketing

// MARK: - MarketingKindSidebarTests

@Suite("MarketingKind")
struct MarketingKindSidebarTests {

    @Test("allCases contains exactly four kinds")
    func allCasesCount() {
        #expect(MarketingKind.allCases.count == 4)
    }

    @Test("allCases order is campaigns, coupons, referrals, reviews")
    func allCasesOrder() {
        let expected: [MarketingKind] = [.campaigns, .coupons, .referrals, .reviews]
        #expect(MarketingKind.allCases == expected)
    }

    @Test("all displayNames are non-empty", arguments: MarketingKind.allCases)
    func displayNamesNonEmpty(kind: MarketingKind) {
        #expect(!kind.displayName.isEmpty)
    }

    @Test("all systemImages are non-empty", arguments: MarketingKind.allCases)
    func systemImagesNonEmpty(kind: MarketingKind) {
        #expect(!kind.systemImage.isEmpty)
    }

    @Test("displayNames are unique")
    func displayNamesUnique() {
        let names = MarketingKind.allCases.map { $0.displayName }
        let unique = Set(names)
        #expect(names.count == unique.count)
    }

    @Test("id equals rawValue", arguments: MarketingKind.allCases)
    func idEqualsRawValue(kind: MarketingKind) {
        #expect(kind.id == kind.rawValue)
    }

    @Test("campaigns rawValue is 'campaigns'")
    func campaignsRawValue() {
        #expect(MarketingKind.campaigns.rawValue == "campaigns")
    }

    @Test("coupons rawValue is 'coupons'")
    func couponsRawValue() {
        #expect(MarketingKind.coupons.rawValue == "coupons")
    }

    @Test("referrals rawValue is 'referrals'")
    func referralsRawValue() {
        #expect(MarketingKind.referrals.rawValue == "referrals")
    }

    @Test("reviews rawValue is 'reviews'")
    func reviewsRawValue() {
        #expect(MarketingKind.reviews.rawValue == "reviews")
    }

    @Test("campaigns displayName is 'Campaigns'")
    func campaignsDisplayName() {
        #expect(MarketingKind.campaigns.displayName == "Campaigns")
    }

    @Test("coupons displayName is 'Coupons'")
    func couponsDisplayName() {
        #expect(MarketingKind.coupons.displayName == "Coupons")
    }

    @Test("referrals displayName is 'Referrals'")
    func referralsDisplayName() {
        #expect(MarketingKind.referrals.displayName == "Referrals")
    }

    @Test("reviews displayName is 'Reviews'")
    func reviewsDisplayName() {
        #expect(MarketingKind.reviews.displayName == "Reviews")
    }

    @Test("CaseIterable conforms (kind is Sendable)", arguments: MarketingKind.allCases)
    func sendableConformance(kind: MarketingKind) {
        let _: any Sendable = kind
        // If this compiles and runs, Sendable conformance is verified.
        #expect(Bool(true))
    }
}
