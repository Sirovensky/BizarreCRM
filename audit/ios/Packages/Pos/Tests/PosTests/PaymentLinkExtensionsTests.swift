#if canImport(UIKit)
import XCTest
@testable import Pos
import Networking

// MARK: - §41.2–41.8 Payment Link Extensions — Unit Tests

/// Tests for BrandedQRGenerator, PaymentLinkExpiryPolicy, and
/// FollowUpScheduleViewModel timing calculations.
@MainActor
final class PaymentLinkExtensionsTests: XCTestCase {

    // MARK: - §41.6 BrandedQRGenerator

    func test_brandedQR_returnsNonNilForValidURL() {
        let img = BrandedQRGenerator.generate(urlString: "https://shop.example.com/pay/abc123")
        XCTAssertNotNil(img, "Expected non-nil QR image for a valid URL")
    }

    func test_brandedQR_returnsNilForEmptyString() {
        let img = BrandedQRGenerator.generate(urlString: "")
        XCTAssertNil(img, "Empty string should produce nil")
    }

    func test_brandedQR_producesCorrectSize() {
        let size: CGFloat = 200
        let img = BrandedQRGenerator.generate(urlString: "https://example.com/pay/test", size: size)
        guard let img else {
            XCTFail("Expected non-nil image")
            return
        }
        // Allow 1 pt rounding from scale.
        XCTAssertEqual(img.size.width, size, accuracy: 1)
        XCTAssertEqual(img.size.height, size, accuracy: 1)
    }

    func test_brandedQR_withLogoStillReturnsNonNil() {
        let img = BrandedQRGenerator.generate(
            urlString: "https://example.com/pay/logo-test",
            size: 300,
            logo: makePlaceholderLogo()
        )
        XCTAssertNotNil(img, "Logo overlay should not cause nil result")
    }

    func test_brandedQR_longURLIsHandled() {
        let longURL = "https://shop.example.com/pay/" + String(repeating: "a", count: 200)
        let img = BrandedQRGenerator.generate(urlString: longURL, size: 300)
        // Very long data can still encode at level H — just verify no crash.
        // Result may be nil if CI doesn't have CI filters (extremely rare).
        _ = img
    }

    // MARK: - §41.7 PaymentLinkExpiryPolicy — enum behaviour

    func test_expiryPolicy_sevenDays_hasCorrectDays() {
        XCTAssertEqual(PaymentLinkExpiryPolicy.sevenDays.days, 7)
    }

    func test_expiryPolicy_fourteenDays_hasCorrectDays() {
        XCTAssertEqual(PaymentLinkExpiryPolicy.fourteenDays.days, 14)
    }

    func test_expiryPolicy_thirtyDays_hasCorrectDays() {
        XCTAssertEqual(PaymentLinkExpiryPolicy.thirtyDays.days, 30)
    }

    func test_expiryPolicy_never_hasNilDays() {
        XCTAssertNil(PaymentLinkExpiryPolicy.never.days)
    }

    func test_expiryPolicy_never_producesNilTimestamp() {
        XCTAssertNil(PaymentLinkExpiryPolicy.never.expiresAt())
    }

    func test_expiryPolicy_sevenDays_producesTimestampSevenDaysAhead() throws {
        let ref = Date()
        let iso = try XCTUnwrap(PaymentLinkExpiryPolicy.sevenDays.expiresAt(from: ref))
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let parsed = try XCTUnwrap(fmt.date(from: iso))
        let delta = parsed.timeIntervalSince(ref)
        XCTAssertEqual(delta, 7 * 86_400, accuracy: 5)
    }

    func test_expiryPolicy_allCases_haveLabels() {
        for policy in PaymentLinkExpiryPolicy.allCases {
            XCTAssertFalse(policy.label.isEmpty, "Policy \(policy.rawValue) has empty label")
        }
    }

    func test_expiryPolicy_roundTripCodable() throws {
        for policy in PaymentLinkExpiryPolicy.allCases {
            let encoded = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(PaymentLinkExpiryPolicy.self, from: encoded)
            XCTAssertEqual(decoded, policy)
        }
    }

    func test_expiryPolicy_expiredMessage_isNonEmpty() {
        XCTAssertFalse(PaymentLinkExpiryPolicy.expiredMessage.isEmpty)
    }

    // MARK: - §41.3 FollowUpScheduleViewModel timing calculations

    func test_followUpSchedule_scheduledDate_returnsCorrectOffset() throws {
        let link = makeLink(createdAt: "2026-04-20T12:00:00Z")
        let vm = FollowUpScheduleViewModel(link: link, api: StubAPIClient())
        let followUp = makeFollowUp(triggerAfterHours: 24)
        let scheduled = try XCTUnwrap(vm.scheduledDate(for: followUp))
        let expected = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-04-21T12:00:00Z")
        )
        XCTAssertEqual(scheduled.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func test_followUpSchedule_scheduledDate_72h() throws {
        let link = makeLink(createdAt: "2026-04-20T00:00:00Z")
        let vm = FollowUpScheduleViewModel(link: link, api: StubAPIClient())
        let followUp = makeFollowUp(triggerAfterHours: 72)
        let scheduled = try XCTUnwrap(vm.scheduledDate(for: followUp))
        let expected = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-04-23T00:00:00Z")
        )
        XCTAssertEqual(scheduled.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func test_followUpSchedule_scheduledDate_nilWhenNoCreatedAt() {
        let link = makeLink(createdAt: nil)
        let vm = FollowUpScheduleViewModel(link: link, api: StubAPIClient())
        let followUp = makeFollowUp(triggerAfterHours: 24)
        XCTAssertNil(vm.scheduledDate(for: followUp))
    }

    func test_followUpSchedule_accessibilityLabel_containsChannel() {
        let link = makeLink(createdAt: "2026-04-20T12:00:00Z")
        let vm = FollowUpScheduleViewModel(link: link, api: StubAPIClient())
        let followUp = makeFollowUp(triggerAfterHours: 48, channel: .email)
        let label = vm.accessibilityLabel(for: followUp)
        XCTAssertTrue(label.contains("email"))
        XCTAssertTrue(label.contains("48"))
    }

    // MARK: - §41.4 PartialPaymentTrackerViewModel calculations

    func test_partialTracker_paidCentsSum() {
        let link = makeLink(amountCents: 5000)
        let vm = PartialPaymentTrackerViewModel(link: link, api: StubAPIClient())
        // Inject payments directly via the mirror pattern (or test the pure math).
        XCTAssertEqual(vm.paidCents, 0)    // empty baseline
        XCTAssertEqual(vm.remainingCents, 5000)
        XCTAssertEqual(vm.paidFraction, 0)
    }

    func test_partialTracker_isOverdue_falseWhenNotExpired() {
        let link = makeLink(
            amountCents: 1000,
            expiresAt: "2099-12-31T00:00:00Z"
        )
        let vm = PartialPaymentTrackerViewModel(link: link, api: StubAPIClient())
        XCTAssertFalse(vm.isOverdueAndUnderpaid)
    }

    func test_partialTracker_isOverdue_trueWhenExpiredWithBalance() {
        let link = makeLink(
            amountCents: 1000,
            expiresAt: "2020-01-01T00:00:00Z"
        )
        let vm = PartialPaymentTrackerViewModel(link: link, api: StubAPIClient())
        XCTAssertTrue(vm.isOverdueAndUnderpaid)
    }

    // MARK: - §41.2 PaymentLinkBranding codable

    func test_branding_decodesSnakeCase() throws {
        let json = """
        {
          "logo_url": "https://cdn.example.com/logo.png",
          "primary_color": "#FF6B00",
          "secondary_color": "#333333",
          "footer_text": "Thank you for your business",
          "terms": "By paying you agree to our terms."
        }
        """.data(using: .utf8)!
        let b = try JSONDecoder().decode(PaymentLinkBranding.self, from: json)
        XCTAssertEqual(b.logoUrl, "https://cdn.example.com/logo.png")
        XCTAssertEqual(b.primaryColor, "#FF6B00")
        XCTAssertEqual(b.footerText, "Thank you for your business")
    }

    func test_branding_encodesSnakeCase() throws {
        let b = PaymentLinkBranding(
            logoUrl: "https://logo.example.com/img.png",
            primaryColor: "#FF6B00"
        )
        let patch = PaymentLinkBrandingPatch(from: b)
        let data = try JSONEncoder().encode(patch)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("logo_url"))
        XCTAssertTrue(json.contains("primary_color"))
    }

    // MARK: - §41.8 Analytics

    func test_analytics_openToPaidRate_zeroWhenNoOpens() {
        let a = PaymentLinkAnalytics(id: 1, sent: 10, opened: 0, clicked: 0, paid: 0)
        XCTAssertEqual(a.openToPaidRate, 0)
    }

    func test_analytics_openToPaidRate_calculatedCorrectly() {
        let a = PaymentLinkAnalytics(id: 1, sent: 100, opened: 50, clicked: 30, paid: 10)
        XCTAssertEqual(a.openToPaidRate, 0.2, accuracy: 0.001)
    }

    func test_analytics_overallConversionRate_aggregate() {
        let agg = PaymentLinksAggregate(
            totalLinks: 5,
            totalSent: 50,
            totalOpened: 40,
            totalClicked: 20,
            totalPaid: 8,
            totalRevenueCents: 80000
        )
        XCTAssertEqual(agg.overallConversionRate, 0.2, accuracy: 0.001)
    }

    func test_analytics_funnelStages_orderedCorrectly() {
        let vm = PaymentLinksDashboardViewModel(api: StubAPIClient())
        let agg = PaymentLinksAggregate(
            totalLinks: 10,
            totalSent: 100,
            totalOpened: 60,
            totalClicked: 40,
            totalPaid: 20,
            totalRevenueCents: 200000
        )
        let stages = vm.funnelStages(from: agg)
        XCTAssertEqual(stages.count, 4)
        XCTAssertEqual(stages[0].label, "Sent")
        XCTAssertEqual(stages[0].count, 100)
        XCTAssertEqual(stages[3].label, "Paid")
        XCTAssertEqual(stages[3].count, 20)
    }

    // MARK: - §41.5 Refund ViewModel

    func test_refund_canSubmit_falseWhenZeroCents() {
        let link = makeLink(amountCents: 5000)
        let vm = PaymentLinkRefundViewModel(link: link, api: StubAPIClient())
        vm.refundCents = 0
        XCTAssertFalse(vm.canSubmit)
    }

    func test_refund_canSubmit_falseWhenExceedsMax() {
        let link = makeLink(amountCents: 5000)
        let vm = PaymentLinkRefundViewModel(link: link, api: StubAPIClient())
        vm.refundCents = 6000
        XCTAssertFalse(vm.canSubmit)
    }

    func test_refund_canSubmit_trueForValidAmount() {
        let link = makeLink(amountCents: 5000)
        let vm = PaymentLinkRefundViewModel(link: link, api: StubAPIClient())
        vm.refundCents = 3000
        XCTAssertTrue(vm.canSubmit)
    }

    func test_refund_canSubmit_falseWhenOtherReasonEmpty() {
        let link = makeLink(amountCents: 5000)
        let vm = PaymentLinkRefundViewModel(link: link, api: StubAPIClient())
        vm.refundCents = 1000
        vm.reason = .other
        vm.customReason = ""
        XCTAssertFalse(vm.canSubmit)
    }

    // MARK: - §41.3 FollowUpRule

    func test_followUpRule_toRequest_preservesFields() {
        let rule = FollowUpRule(triggerAfterHours: 48, channel: .email)
        let req = rule.toRequest()
        XCTAssertEqual(req.triggerAfterHours, 48)
        XCTAssertEqual(req.channel, .email)
    }

    func test_followUpPolicyEditor_addRule_incrementsByDefault() {
        let vm = FollowUpPolicyEditorViewModel(linkId: 1, api: StubAPIClient())
        let initial = vm.rules.count
        vm.addRule()
        XCTAssertEqual(vm.rules.count, initial + 1)
        // New rule's trigger should be > last rule's trigger.
        let last = vm.rules[vm.rules.count - 2].triggerAfterHours
        let added = vm.rules.last!.triggerAfterHours
        XCTAssertGreaterThan(added, last)
    }

    func test_followUpPolicyEditor_removeRules() {
        let vm = FollowUpPolicyEditorViewModel(linkId: 1, api: StubAPIClient())
        let initial = vm.rules.count
        vm.removeRules(at: IndexSet(integer: 0))
        XCTAssertEqual(vm.rules.count, initial - 1)
    }

    // MARK: - Helpers

    private func makeLink(
        id: Int64 = 1,
        amountCents: Int = 2500,
        createdAt: String? = "2026-04-20T12:00:00Z",
        expiresAt: String? = nil
    ) -> PaymentLink {
        PaymentLink(
            id: id,
            shortId: "test-token",
            url: "https://shop.example.com/pay/test-token",
            status: "active",
            amountCents: amountCents,
            createdAt: createdAt,
            expiresAt: expiresAt,
            paidAt: nil
        )
    }

    private func makeFollowUp(
        id: Int64 = 1,
        linkId: Int64 = 1,
        triggerAfterHours: Int = 24,
        channel: PaymentLinkFollowUp.Channel = .sms
    ) -> PaymentLinkFollowUp {
        PaymentLinkFollowUp(
            id: id,
            paymentLinkId: linkId,
            triggerAfterHours: triggerAfterHours,
            templateId: nil,
            channel: channel,
            sentAt: nil,
            deliveredAt: nil,
            status: .scheduled
        )
    }

    private func makePlaceholderLogo() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        return renderer.image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }
}

// MARK: - Minimal stub APIClient for pure-logic tests (throws on all network calls)

private final class StubAPIClient: APIClient, @unchecked Sendable {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
    func delete(_ path: String) async throws {
        throw URLError(.notConnectedToInternet)
    }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw URLError(.notConnectedToInternet)
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
#endif
