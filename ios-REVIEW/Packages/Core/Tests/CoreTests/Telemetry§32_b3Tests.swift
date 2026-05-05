import XCTest
@testable import Core

// §32 batch-3 tests
//
// Covers the 5 §32 ActionPlan items wired in this commit:
//   • §32.0 single-sink — `TenantServerAnalyticsSink.defaultEndpointProvider`
//     resolves the URL at send-time from `UserDefaults`.
//   • §32.4 sync helpers — `Analytics.trackSyncStart/Complete/Failed`.
//   • §32.4 POS sale helpers — `Analytics.trackPosSaleComplete/Failed`.
//   • §32.4 perf helpers — `Analytics.trackColdLaunchMs / trackFirstPaintMs`.
//   • §32.6 field-shape detection fallback — `LogRedactor.redactWithLikelyPIIFallback`.

@MainActor
final class Telemetry§32_b3Tests: XCTestCase {

    // MARK: — §32.0 single-sink endpoint provider

    func test_defaultEndpointProvider_returnsNil_whenBaseURLMissing() {
        let suite = "test.sink.endpoint.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let provider = TenantServerAnalyticsSink.defaultEndpointProvider(
            userDefaults: defaults,
            baseURLKey: "com.bizarrecrm.apiBaseURL",
            path: "telemetry/events"
        )
        XCTAssertNil(provider(), "No tenant configured → provider must return nil")
    }

    func test_defaultEndpointProvider_appendsPath_whenBaseURLPresent() {
        let suite = "test.sink.endpoint.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set("https://acme.bizarrecrm.com", forKey: "com.bizarrecrm.apiBaseURL")

        let provider = TenantServerAnalyticsSink.defaultEndpointProvider(
            userDefaults: defaults,
            baseURLKey: "com.bizarrecrm.apiBaseURL",
            path: "telemetry/events"
        )
        XCTAssertEqual(
            provider()?.absoluteString,
            "https://acme.bizarrecrm.com/telemetry/events"
        )
    }

    func test_endpointProvider_isReResolvedAtFlush_followsTenantSwitch() async {
        let suite = "test.sink.tenant.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set("https://tenant-a.example.com", forKey: "com.bizarrecrm.apiBaseURL")

        let consent = AnalyticsConsentManager(defaults: defaults)
        consent.optIn()
        let session = AnalyticsSinkStub()
        let provider = TenantServerAnalyticsSink.defaultEndpointProvider(
            userDefaults: defaults,
            baseURLKey: "com.bizarrecrm.apiBaseURL",
            path: "telemetry/events"
        )
        let sink = TenantServerAnalyticsSink(
            endpointProvider: provider,
            consentManager: consent,
            session: session,
            batchSize: 1
        )

        let payload = AnalyticsEventPayload(
            event: .appLaunched,
            timestamp: Date(),
            properties: [:],
            sessionId: UUID().uuidString,
            tenantSlug: "tenant-a",
            appVersion: "1.0.0",
            platform: "iOS"
        )
        await sink.enqueue(payload)
        XCTAssertEqual(
            session.capturedRequests.last?.url?.host, "tenant-a.example.com",
            "First flush must hit tenant-a"
        )

        // Tenant switch: change the base URL and flush again.
        defaults.set("https://tenant-b.example.com", forKey: "com.bizarrecrm.apiBaseURL")
        await sink.enqueue(payload)
        XCTAssertEqual(
            session.capturedRequests.last?.url?.host, "tenant-b.example.com",
            "After switch, next flush must hit tenant-b (URL resolved at send-time)"
        )
    }

    // MARK: — §32.4 sync lifecycle helpers

    func test_analyticsEvent_syncTriad_existsInCatalog() {
        XCTAssertEqual(AnalyticsEvent.syncStarted.rawValue, "sync.started")
        XCTAssertEqual(AnalyticsEvent.syncCompleted.rawValue, "sync.completed")
        XCTAssertEqual(AnalyticsEvent.syncFailed.rawValue, "sync.failed")
        XCTAssertEqual(AnalyticsEvent.syncStarted.category, .domain)
    }

    // MARK: — §32.4 POS sale helpers

    func test_analyticsEvent_posSale_existsInCatalog() {
        XCTAssertEqual(AnalyticsEvent.posSaleComplete.rawValue, "pos.sale.complete")
        XCTAssertEqual(AnalyticsEvent.posSaleFailed.rawValue, "pos.sale.failed")
        XCTAssertEqual(AnalyticsEvent.posSaleComplete.category, .domain)
    }

    // MARK: — §32.4 perf helpers

    func test_analyticsEvent_perfLaunch_existsInCatalog() {
        XCTAssertEqual(AnalyticsEvent.coldLaunchMs.rawValue, "perf.cold_launch_ms")
        XCTAssertEqual(AnalyticsEvent.firstPaintMs.rawValue, "perf.first_paint_ms")
        XCTAssertEqual(AnalyticsEvent.coldLaunchMs.category, .domain)
    }

    // MARK: — §32.6 field-shape detection fallback (`*LIKELY_PII*`)

    func test_redactWithLikelyPIIFallback_replacesUntaggedLongDigitRun() {
        // 11 contiguous digits — survives strict (no labelled prefix), caught by fallback
        let input = "Reference 12345678901 in log"
        let result = LogRedactor.redactWithLikelyPIIFallback(input)
        XCTAssertTrue(result.contains("*LIKELY_PII*"),
            "Untagged long digit run must be replaced; got \(result)")
        XCTAssertFalse(result.contains("12345678901"),
            "Raw digits must not survive fallback pass")
    }

    func test_redactWithLikelyPIIFallback_replacesObfuscatedEmail() {
        let input = "ping user [at] example.com please"
        let result = LogRedactor.redactWithLikelyPIIFallback(input)
        XCTAssertTrue(result.contains("*LIKELY_PII*"),
            "Obfuscated 'user [at] example.com' should be flagged; got \(result)")
    }

    func test_redactWithLikelyPIIFallback_keepsCanonicalPlaceholders() {
        // Strict pass should still emit *CUSTOMER_EMAIL* — the fallback must not
        // overwrite an already-tagged placeholder with `*LIKELY_PII*`.
        let input = "user@example.com checking in"
        let result = LogRedactor.redactWithLikelyPIIFallback(input)
        XCTAssertTrue(result.contains("*CUSTOMER_EMAIL*"),
            "Strict-pass placeholder must survive fallback; got \(result)")
        XCTAssertFalse(result.contains("user@example.com"),
            "Raw email must be redacted")
    }

    func test_redactWithLikelyPIIFallback_doesNotMaulShortNumbers() {
        // Short identifiers (order numbers, status codes, version components) must
        // not collide with the fallback rule.
        let input = "status=200 request_id=42"
        let result = LogRedactor.redactWithLikelyPIIFallback(input)
        XCTAssertTrue(result.contains("200"),
            "3-digit status code must survive fallback")
        XCTAssertTrue(result.contains("42"),
            "Short request id must survive fallback")
    }
}
