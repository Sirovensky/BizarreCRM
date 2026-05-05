import XCTest
@testable import Core

// §71 Privacy-first Analytics — unit tests for AnalyticsEventMapper

// MARK: - AnalyticsEventMapperTests

final class AnalyticsEventMapperTests: XCTestCase {

    // MARK: - TelemetryRecord structure

    func test_buildRecord_setsEventName() {
        let record = AnalyticsEventMapper.buildRecord(for: .ticketCreated(priority: "high"))
        XCTAssertEqual(record.name, "ticket.created")
    }

    func test_buildRecord_setsCorrectCategory() {
        let record = AnalyticsEventMapper.buildRecord(for: .appLaunched(coldStart: true))
        XCTAssertEqual(record.category, .appLifecycle)
    }

    func test_buildRecord_domainEvent_hasCorrectCategory() {
        let record = AnalyticsEventMapper.buildRecord(for: .saleCompleted(totalCents: 100, itemCount: 1))
        XCTAssertEqual(record.category, .domain)
    }

    func test_buildRecord_navigationEvent_hasCorrectCategory() {
        let record = AnalyticsEventMapper.buildRecord(for: .tappedView(screen: "tickets"))
        XCTAssertEqual(record.category, .navigation)
    }

    func test_buildRecord_errorEvent_hasCorrectCategory() {
        let record = AnalyticsEventMapper.buildRecord(for: .errorPresented(domain: "Net", code: 503))
        XCTAssertEqual(record.category, .error)
    }

    // MARK: - Properties preservation

    func test_buildRecord_preservesStructuralProperties() {
        let record = AnalyticsEventMapper.buildRecord(for: .openedDetail(entity: .invoice, id: "inv_7"))
        XCTAssertEqual(record.properties["entity"], "invoice")
        XCTAssertEqual(record.properties["id"], "inv_7")
    }

    func test_buildRecord_preservesNumericProperties() {
        let record = AnalyticsEventMapper.buildRecord(
            for: .saleCompleted(totalCents: 4999, itemCount: 3)
        )
        XCTAssertEqual(record.properties["total_cents"], "4999")
        XCTAssertEqual(record.properties["item_count"], "3")
    }

    func test_buildRecord_emptyPropertiesEvent_hasEmptyOrContextOnlyProperties() {
        let record = AnalyticsEventMapper.buildRecord(for: .appBackgrounded)
        // No structural properties; only possible key is _dispatch_ctx which may be absent if empty
        let keys = Set(record.properties.keys)
        let allowedKeys: Set<String> = ["_dispatch_ctx"]
        XCTAssertTrue(keys.isSubset(of: allowedKeys),
                      "appBackgrounded should have no unexpected properties, found: \(keys)")
    }

    // MARK: - PII redaction

    func test_buildRecord_doesNotIncludeForbiddenKeyValues() {
        // Inject a property with a structurally safe key but an email in the value
        // via a custom event that embeds an email in a note field.
        // We simulate by calling mapper directly with a mocked "note" that has an email.
        // The mapper uses TelemetryRedactor which should strip it.
        let event = PrivacyEvent.errorPresented(domain: "user@test.com", code: 500)
        let record = AnalyticsEventMapper.buildRecord(for: event)
        // The domain value contained an email address — redactor should have masked it.
        if let domain = record.properties["error_domain"] {
            XCTAssertFalse(domain.contains("@"),
                           "Email pattern in error_domain should be redacted, got: \(domain)")
        }
    }

    func test_buildRecord_forbiddenPropertyKeys_areDropped() {
        // PrivacyEvent.properties should never produce PII keys, but the mapper
        // has a defence layer anyway. We verify it using the mapper's internal
        // guard: any key returned by isForbiddenField is removed.
        // Since we can't inject arbitrary keys through a typed event, we verify
        // that all records produced from the full event set are free of forbidden keys.
        let records = allTestEvents.map { AnalyticsEventMapper.buildRecord(for: $0) }
        for record in records {
            for key in record.properties.keys {
                XCTAssertFalse(
                    AnalyticsPIIGuard.isForbiddenField(key),
                    "Record '\(record.name)' contains forbidden key '\(key)'"
                )
            }
        }
    }

    // MARK: - SafeValue marker

    func test_buildRecord_withMarker_attachesDispatchCtx() {
        let marker = AnalyticsPIIGuard.markSafe("feature-x")
        let record = AnalyticsEventMapper.buildRecord(for: .customerCreated, safeMarker: marker)
        XCTAssertEqual(record.properties["_dispatch_ctx"], "feature-x")
    }

    func test_buildRecord_withEmptyMarker_doesNotAttachCtx() {
        let marker = AnalyticsPIIGuard.markSafe("")
        let record = AnalyticsEventMapper.buildRecord(for: .customerCreated, safeMarker: marker)
        XCTAssertNil(record.properties["_dispatch_ctx"],
                     "Empty marker should not attach _dispatch_ctx")
    }

    // MARK: - Timestamp injection

    func test_buildRecord_usesInjectedTimestamp() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let record = AnalyticsEventMapper.buildRecord(
            for: .appLaunched(coldStart: false),
            timestamp: fixedDate
        )
        XCTAssertEqual(record.timestamp, fixedDate)
    }

    // MARK: - All events produce valid records

    func test_allTestEvents_produceNonEmptyName() {
        for event in allTestEvents {
            let record = AnalyticsEventMapper.buildRecord(for: event)
            XCTAssertFalse(record.name.isEmpty,
                           "Record for \(event.name) should have non-empty name")
        }
    }

    // MARK: - Helpers

    private var allTestEvents: [PrivacyEvent] {
        [
            .tappedView(screen: "s"),
            .openedDetail(entity: .ticket, id: "t_1"),
            .formSubmitted(formName: "f", fieldCount: 2),
            .formDiscarded(formName: "f"),
            .saleCompleted(totalCents: 100, itemCount: 1),
            .refundIssued(amountCents: 50),
            .ticketCreated(priority: "low"),
            .ticketStatusChanged(fromStatus: "open", toStatus: "done"),
            .customerCreated,
            .inventoryAdjusted(itemId: "i_1", delta: 1),
            .invoiceSent(invoiceId: "inv_1"),
            .paymentRecorded(method: "cash", amountCents: 500),
            .appLaunched(coldStart: true),
            .appBackgrounded,
            .sessionEnded(durationSeconds: 60),
            .commandPaletteOpened,
            .commandExecuted(commandId: "cmd_x"),
            .featureFirstUse(featureId: "feat_y"),
            .searchPerformed(resultCount: 5),
            .errorPresented(domain: "Err", code: 0),
        ]
    }
}
