import XCTest
@testable import Leads
@testable import Networking

final class LeadSourceAnalyticsTests: XCTestCase {

    // MARK: - computeStats

    func test_emptyLeads_allZeroStats() {
        let stats = LeadSourceAnalytics.computeStats(from: [])
        XCTAssertEqual(stats.count, LeadSource.allCases.count)
        for s in stats {
            XCTAssertEqual(s.totalLeads, 0)
            XCTAssertEqual(s.convertedLeads, 0)
            XCTAssertEqual(s.conversionRate, 0)
        }
    }

    func test_singleWonLead_100pctConversion() {
        let lead = Lead(id: 1, status: "won", source: "referral")
        let stats = LeadSourceAnalytics.computeStats(from: [lead])
        let referralStats = stats.first(where: { $0.source == .referral })!
        XCTAssertEqual(referralStats.totalLeads, 1)
        XCTAssertEqual(referralStats.convertedLeads, 1)
        XCTAssertEqual(referralStats.conversionRate, 1.0, accuracy: 0.001)
    }

    func test_mixedLeads_correctCounts() {
        let leads: [Lead] = [
            Lead(id: 1, status: "won", source: "web"),
            Lead(id: 2, status: "new", source: "web"),
            Lead(id: 3, status: "won", source: "web"),
            Lead(id: 4, status: "new", source: "referral"),
        ]
        let stats = LeadSourceAnalytics.computeStats(from: leads)
        let webStats      = stats.first(where: { $0.source == .web })!
        let referralStats = stats.first(where: { $0.source == .referral })!

        XCTAssertEqual(webStats.totalLeads, 3)
        XCTAssertEqual(webStats.convertedLeads, 2)
        XCTAssertEqual(webStats.conversionRate, 2.0 / 3.0, accuracy: 0.001)

        XCTAssertEqual(referralStats.totalLeads, 1)
        XCTAssertEqual(referralStats.convertedLeads, 0)
        XCTAssertEqual(referralStats.conversionRate, 0)
    }

    func test_conversionRateLabel_formatsPercent() {
        let stats = LeadSourceStats(source: .web, totalLeads: 4, convertedLeads: 1)
        XCTAssertEqual(stats.conversionRateLabel, "25%")
    }

    func test_zeroTotalLeads_conversionRate_isZero() {
        let stats = LeadSourceStats(source: .phone, totalLeads: 0, convertedLeads: 0)
        XCTAssertEqual(stats.conversionRate, 0)
    }

    // MARK: - topSource

    func test_topSource_returnsHighestConversionSource() {
        let leads: [Lead] = [
            Lead(id: 1, status: "won",  source: "referral"),
            Lead(id: 2, status: "won",  source: "referral"),
            Lead(id: 3, status: "new",  source: "web"),
            Lead(id: 4, status: "won",  source: "web"),
        ]
        let top = LeadSourceAnalytics.topSource(from: leads)
        XCTAssertEqual(top, .referral, "Referral (100%) should beat web (50%)")
    }

    func test_topSource_nilWhenNoLeads() {
        let top = LeadSourceAnalytics.topSource(from: [])
        XCTAssertNil(top)
    }

    // MARK: - LeadSource.from

    func test_fromRaw_caseInsensitive() {
        XCTAssertEqual(LeadSource.from("REFERRAL"), .referral)
        XCTAssertEqual(LeadSource.from("Web"),      .web)
        XCTAssertEqual(LeadSource.from("PHONE"),    .phone)
    }

    func test_fromRaw_hyphenNormalized() {
        XCTAssertEqual(LeadSource.from("walk-in"), .walkIn)
    }

    func test_fromRaw_unknownFallsToOther() {
        XCTAssertEqual(LeadSource.from("mystery"), .other)
        XCTAssertEqual(LeadSource.from(nil),       .other)
    }

    // MARK: - Sorting

    func test_computeStats_sortedByConversionDesc() {
        let leads: [Lead] = [
            Lead(id: 1, status: "new", source: "referral"),      // 0%
            Lead(id: 2, status: "won", source: "phone"),          // 100%
        ]
        let stats = LeadSourceAnalytics.computeStats(from: leads)
        let rates = stats.filter { $0.totalLeads > 0 }.map { $0.conversionRate }
        XCTAssertTrue(zip(rates, rates.dropFirst()).allSatisfy { $0 >= $1 }, "Stats should be sorted descending")
    }

    // MARK: - All sources represented

    func test_allSourcesRepresented() {
        let stats = LeadSourceAnalytics.computeStats(from: [])
        let sources = Set(stats.map { $0.source })
        let expected = Set(LeadSource.allCases)
        XCTAssertEqual(sources, expected)
    }
}
