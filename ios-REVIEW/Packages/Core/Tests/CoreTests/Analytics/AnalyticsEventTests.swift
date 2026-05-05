import XCTest
@testable import Core

// §71 Privacy-first Analytics — unit tests for AnalyticsEvent enum

// MARK: - AnalyticsEventTests

final class AnalyticsEventTests: XCTestCase {

    // MARK: - name property

    func test_tappedView_hasExpectedName() {
        let event = PrivacyEvent.tappedView(screen: "dashboard")
        XCTAssertEqual(event.name, "ui.tapped_view")
    }

    func test_openedDetail_hasExpectedName() {
        let event = PrivacyEvent.openedDetail(entity: .ticket, id: "t_1")
        XCTAssertEqual(event.name, "ui.opened_detail")
    }

    func test_formSubmitted_hasExpectedName() {
        let event = PrivacyEvent.formSubmitted(formName: "new_ticket", fieldCount: 4)
        XCTAssertEqual(event.name, "ui.form.submitted")
    }

    func test_formDiscarded_hasExpectedName() {
        let event = PrivacyEvent.formDiscarded(formName: "new_customer")
        XCTAssertEqual(event.name, "ui.form.discarded")
    }

    func test_saleCompleted_hasExpectedName() {
        let event = PrivacyEvent.saleCompleted(totalCents: 999, itemCount: 2)
        XCTAssertEqual(event.name, "pos.sale.completed")
    }

    func test_refundIssued_hasExpectedName() {
        let event = PrivacyEvent.refundIssued(amountCents: 500)
        XCTAssertEqual(event.name, "pos.refund.issued")
    }

    func test_ticketCreated_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.ticketCreated(priority: "high").name, "ticket.created")
    }

    func test_ticketStatusChanged_hasExpectedName() {
        XCTAssertEqual(
            PrivacyEvent.ticketStatusChanged(fromStatus: "open", toStatus: "closed").name,
            "ticket.status.changed"
        )
    }

    func test_customerCreated_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.customerCreated.name, "customer.created")
    }

    func test_inventoryAdjusted_hasExpectedName() {
        XCTAssertEqual(
            PrivacyEvent.inventoryAdjusted(itemId: "i_1", delta: -3).name,
            "inventory.adjusted"
        )
    }

    func test_invoiceSent_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.invoiceSent(invoiceId: "inv_42").name, "invoice.sent")
    }

    func test_paymentRecorded_hasExpectedName() {
        XCTAssertEqual(
            PrivacyEvent.paymentRecorded(method: "card", amountCents: 1200).name,
            "payment.recorded"
        )
    }

    func test_appLaunched_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.appLaunched(coldStart: true).name, "app.launched")
    }

    func test_appBackgrounded_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.appBackgrounded.name, "app.backgrounded")
    }

    func test_sessionEnded_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.sessionEnded(durationSeconds: 120).name, "session.ended")
    }

    func test_commandPaletteOpened_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.commandPaletteOpened.name, "command_palette.opened")
    }

    func test_commandExecuted_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.commandExecuted(commandId: "cmd_new_ticket").name, "command_palette.executed")
    }

    func test_featureFirstUse_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.featureFirstUse(featureId: "kiosk_mode").name, "feature.first_use")
    }

    func test_searchPerformed_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.searchPerformed(resultCount: 7).name, "search.performed")
    }

    func test_errorPresented_hasExpectedName() {
        XCTAssertEqual(PrivacyEvent.errorPresented(domain: "AppError", code: 404).name, "error.presented")
    }

    // MARK: - telemetryCategory mapping

    func test_navigationEvents_mapToNavigationCategory() {
        let navEvents: [PrivacyEvent] = [
            .tappedView(screen: "tickets"),
            .openedDetail(entity: .customer, id: "c_1"),
            .commandPaletteOpened,
            .commandExecuted(commandId: "cmd_search"),
        ]
        for event in navEvents {
            XCTAssertEqual(event.telemetryCategory, .navigation,
                           "\(event.name) should map to .navigation")
        }
    }

    func test_domainEvents_mapToDomainCategory() {
        let domainEvents: [PrivacyEvent] = [
            .formSubmitted(formName: "ticket", fieldCount: 3),
            .formDiscarded(formName: "invoice"),
            .ticketCreated(priority: "low"),
            .ticketStatusChanged(fromStatus: "open", toStatus: "done"),
            .customerCreated,
            .inventoryAdjusted(itemId: "i_5", delta: 10),
            .invoiceSent(invoiceId: "inv_1"),
            .saleCompleted(totalCents: 100, itemCount: 1),
            .refundIssued(amountCents: 50),
            .paymentRecorded(method: "cash", amountCents: 100),
            .featureFirstUse(featureId: "audit_logs"),
            .searchPerformed(resultCount: 3),
        ]
        for event in domainEvents {
            XCTAssertEqual(event.telemetryCategory, .domain,
                           "\(event.name) should map to .domain")
        }
    }

    func test_lifecycleEvents_mapToAppLifecycleCategory() {
        let lifecycleEvents: [PrivacyEvent] = [
            .appLaunched(coldStart: false),
            .appBackgrounded,
            .sessionEnded(durationSeconds: 300),
        ]
        for event in lifecycleEvents {
            XCTAssertEqual(event.telemetryCategory, .appLifecycle,
                           "\(event.name) should map to .appLifecycle")
        }
    }

    func test_errorPresented_mapsToErrorCategory() {
        XCTAssertEqual(
            PrivacyEvent.errorPresented(domain: "Net", code: 500).telemetryCategory,
            .error
        )
    }

    // MARK: - properties extraction

    func test_tappedView_properties_containScreen() {
        let props = PrivacyEvent.tappedView(screen: "dashboard").properties
        XCTAssertEqual(props["screen"], "dashboard")
    }

    func test_openedDetail_properties_containEntityAndId() {
        let props = PrivacyEvent.openedDetail(entity: .invoice, id: "inv_7").properties
        XCTAssertEqual(props["entity"], "invoice")
        XCTAssertEqual(props["id"], "inv_7")
    }

    func test_formSubmitted_properties_containFormNameAndFieldCount() {
        let props = PrivacyEvent.formSubmitted(formName: "edit_customer", fieldCount: 6).properties
        XCTAssertEqual(props["form"], "edit_customer")
        XCTAssertEqual(props["field_count"], "6")
    }

    func test_saleCompleted_properties_containTotals() {
        let props = PrivacyEvent.saleCompleted(totalCents: 4999, itemCount: 3).properties
        XCTAssertEqual(props["total_cents"], "4999")
        XCTAssertEqual(props["item_count"], "3")
    }

    func test_ticketStatusChanged_properties_containFromAndTo() {
        let props = PrivacyEvent.ticketStatusChanged(fromStatus: "open", toStatus: "resolved").properties
        XCTAssertEqual(props["from_status"], "open")
        XCTAssertEqual(props["to_status"], "resolved")
    }

    func test_inventoryAdjusted_properties_containItemIdAndDelta() {
        let props = PrivacyEvent.inventoryAdjusted(itemId: "sku_999", delta: -5).properties
        XCTAssertEqual(props["item_id"], "sku_999")
        XCTAssertEqual(props["delta"], "-5")
    }

    func test_appLaunched_coldStart_true_isRepresented() {
        let props = PrivacyEvent.appLaunched(coldStart: true).properties
        XCTAssertEqual(props["cold_start"], "true")
    }

    func test_appLaunched_coldStart_false_isRepresented() {
        let props = PrivacyEvent.appLaunched(coldStart: false).properties
        XCTAssertEqual(props["cold_start"], "false")
    }

    func test_errorPresented_properties_containDomainAndCode() {
        let props = PrivacyEvent.errorPresented(domain: "URLError", code: -1009).properties
        XCTAssertEqual(props["error_domain"], "URLError")
        XCTAssertEqual(props["error_code"], "-1009")
    }

    func test_customerCreated_hasEmptyProperties() {
        XCTAssertTrue(PrivacyEvent.customerCreated.properties.isEmpty)
    }

    func test_appBackgrounded_hasEmptyProperties() {
        XCTAssertTrue(PrivacyEvent.appBackgrounded.properties.isEmpty)
    }

    func test_commandPaletteOpened_hasEmptyProperties() {
        XCTAssertTrue(PrivacyEvent.commandPaletteOpened.properties.isEmpty)
    }

    // MARK: - properties must not contain PII field names

    func test_allEventProperties_doNotUseForbiddenKeys() {
        let allEvents: [PrivacyEvent] = [
            .tappedView(screen: "x"),
            .openedDetail(entity: .ticket, id: "t_1"),
            .formSubmitted(formName: "f", fieldCount: 1),
            .formDiscarded(formName: "f"),
            .saleCompleted(totalCents: 100, itemCount: 1),
            .refundIssued(amountCents: 50),
            .ticketCreated(priority: "low"),
            .ticketStatusChanged(fromStatus: "a", toStatus: "b"),
            .customerCreated,
            .inventoryAdjusted(itemId: "i", delta: 1),
            .invoiceSent(invoiceId: "inv_1"),
            .paymentRecorded(method: "card", amountCents: 100),
            .appLaunched(coldStart: true),
            .appBackgrounded,
            .sessionEnded(durationSeconds: 60),
            .commandPaletteOpened,
            .commandExecuted(commandId: "c"),
            .featureFirstUse(featureId: "f"),
            .searchPerformed(resultCount: 0),
            .errorPresented(domain: "Err", code: 0),
        ]
        for event in allEvents {
            for key in event.properties.keys {
                XCTAssertFalse(
                    AnalyticsPIIGuard.isForbiddenField(key),
                    "Event '\(event.name)' uses forbidden PII key '\(key)'"
                )
            }
        }
    }

    // MARK: - Sendable conformance (compile-time)

    func test_analyticsEvent_isSendable() {
        let _: any Sendable = PrivacyEvent.customerCreated
    }

    func test_entityKind_isSendable() {
        let _: any Sendable = EntityKind.ticket
    }
}
