import XCTest
@testable import Core

// MARK: - HandoffTests

/// Tests for `HandoffActivityType`, `HandoffBuilder`, `HandoffParser`,
/// `HandoffEligibility`, and `ClipboardBridge`.
///
/// Coverage targets:
/// - All `HandoffActivityType` cases and their raw values.
/// - `HandoffActivityType(destination:)` init for every eligible and
///   non-eligible destination.
/// - `HandoffBuilder` produces a valid `NSUserActivity` with correct
///   type, title, `webpageURL`, and `userInfo`.
/// - `HandoffParser` round-trips every eligible destination through
///   builder → parser.
/// - `HandoffParser` falls back correctly to `webpageURL` when
///   `userInfo` is absent.
/// - `HandoffEligibility` accepts exactly the four eligible cases and
///   rejects every other destination.
/// - `ClipboardBridge.clipboardPayload` resolves correctly for
///   copyable vs. non-copyable destinations (via the public `copy`
///   return value).

// swiftlint:disable type_body_length file_length

@MainActor
final class HandoffTests: XCTestCase {

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    /// Build an `NSUserActivity` that mimics a Handoff activity arriving from
    /// another device with full `userInfo` (as produced by `HandoffBuilder`).
    private func makeActivity(
        type: HandoffActivityType,
        userInfo: [String: String],
        webpageURL: URL? = nil
    ) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type.activityTypeIdentifier)
        activity.userInfo = userInfo
        if let url = webpageURL {
            activity.webpageURL = url
        }
        return activity
    }

    /// Convenience: build then parse a destination for a round-trip assertion.
    private func roundTrip(
        _ destination: DeepLinkDestination,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let activity = HandoffBuilder.build(from: destination) else {
            XCTFail("HandoffBuilder returned nil for \(destination)", file: file, line: line)
            return
        }
        guard let parsed = HandoffParser.destination(from: activity) else {
            XCTFail("HandoffParser returned nil for activity \(activity.activityType)",
                    file: file, line: line)
            return
        }
        XCTAssertEqual(parsed, destination, file: file, line: line)
    }

    // =========================================================================
    // MARK: - 1. HandoffActivityType raw values
    // =========================================================================

    func test_activityType_ticketDetail_rawValue() {
        XCTAssertEqual(
            HandoffActivityType.ticketDetail.rawValue,
            "com.bizarrecrm.ticket.detail"
        )
    }

    func test_activityType_customerDetail_rawValue() {
        XCTAssertEqual(
            HandoffActivityType.customerDetail.rawValue,
            "com.bizarrecrm.customer.detail"
        )
    }

    func test_activityType_invoiceDetail_rawValue() {
        XCTAssertEqual(
            HandoffActivityType.invoiceDetail.rawValue,
            "com.bizarrecrm.invoice.detail"
        )
    }

    func test_activityType_estimateDetail_rawValue() {
        XCTAssertEqual(
            HandoffActivityType.estimateDetail.rawValue,
            "com.bizarrecrm.estimate.detail"
        )
    }

    func test_activityType_activityTypeIdentifier_matchesRawValue() {
        for type_ in HandoffActivityType.allCases {
            XCTAssertEqual(
                type_.activityTypeIdentifier,
                type_.rawValue,
                "activityTypeIdentifier must equal rawValue for \(type_)"
            )
        }
    }

    // =========================================================================
    // MARK: - 2. HandoffActivityType init(destination:)
    // =========================================================================

    func test_activityType_init_ticket_returnsTicketDetail() {
        let t = HandoffActivityType(
            destination: .ticket(tenantSlug: "acme", id: "T-1")
        )
        XCTAssertEqual(t, .ticketDetail)
    }

    func test_activityType_init_customer_returnsCustomerDetail() {
        let t = HandoffActivityType(
            destination: .customer(tenantSlug: "acme", id: "C-5")
        )
        XCTAssertEqual(t, .customerDetail)
    }

    func test_activityType_init_invoice_returnsInvoiceDetail() {
        let t = HandoffActivityType(
            destination: .invoice(tenantSlug: "acme", id: "INV-9")
        )
        XCTAssertEqual(t, .invoiceDetail)
    }

    func test_activityType_init_estimate_returnsEstimateDetail() {
        let t = HandoffActivityType(
            destination: .estimate(tenantSlug: "acme", id: "EST-7")
        )
        XCTAssertEqual(t, .estimateDetail)
    }

    func test_activityType_init_dashboard_returnsNil() {
        XCTAssertNil(HandoffActivityType(destination: .dashboard(tenantSlug: "acme")))
    }

    func test_activityType_init_lead_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(destination: .lead(tenantSlug: "acme", id: "L-1"))
        )
    }

    func test_activityType_init_appointment_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(
                destination: .appointment(tenantSlug: "acme", id: "APT-1")
            )
        )
    }

    func test_activityType_init_inventory_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(
                destination: .inventory(tenantSlug: "acme", sku: "SKU-1")
            )
        )
    }

    func test_activityType_init_posRoot_returnsNil() {
        XCTAssertNil(HandoffActivityType(destination: .posRoot(tenantSlug: "acme")))
    }

    func test_activityType_init_magicLink_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(
                destination: .magicLink(tenantSlug: "acme", token: "tok12345678")
            )
        )
    }

    func test_activityType_init_smsThread_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(
                destination: .smsThread(tenantSlug: "acme", phone: "+14155550100")
            )
        )
    }

    func test_activityType_init_search_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(
                destination: .search(tenantSlug: "acme", query: "widget")
            )
        )
    }

    func test_activityType_init_timeclock_returnsNil() {
        XCTAssertNil(HandoffActivityType(destination: .timeclock(tenantSlug: "acme")))
    }

    func test_activityType_init_notifications_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(destination: .notifications(tenantSlug: "acme"))
        )
    }

    func test_activityType_init_reports_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(
                destination: .reports(tenantSlug: "acme", name: "revenue")
            )
        )
    }

    func test_activityType_init_auditLogs_returnsNil() {
        XCTAssertNil(HandoffActivityType(destination: .auditLogs(tenantSlug: "acme")))
    }

    func test_activityType_init_settings_returnsNil() {
        XCTAssertNil(
            HandoffActivityType(destination: .settings(tenantSlug: "acme", section: nil))
        )
    }

    // =========================================================================
    // MARK: - 3. HandoffEligibility
    // =========================================================================

    func test_eligibility_ticket_isEligible() {
        XCTAssertTrue(
            HandoffEligibility.isEligible(.ticket(tenantSlug: "acme", id: "T-1"))
        )
    }

    func test_eligibility_customer_isEligible() {
        XCTAssertTrue(
            HandoffEligibility.isEligible(.customer(tenantSlug: "acme", id: "C-1"))
        )
    }

    func test_eligibility_invoice_isEligible() {
        XCTAssertTrue(
            HandoffEligibility.isEligible(.invoice(tenantSlug: "acme", id: "INV-1"))
        )
    }

    func test_eligibility_estimate_isEligible() {
        XCTAssertTrue(
            HandoffEligibility.isEligible(.estimate(tenantSlug: "acme", id: "EST-1"))
        )
    }

    func test_eligibility_dashboard_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(.dashboard(tenantSlug: "acme"))
        )
    }

    func test_eligibility_lead_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(.lead(tenantSlug: "acme", id: "L-1"))
        )
    }

    func test_eligibility_appointment_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(
                .appointment(tenantSlug: "acme", id: "APT-1")
            )
        )
    }

    func test_eligibility_inventory_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(.inventory(tenantSlug: "acme", sku: "S-1"))
        )
    }

    func test_eligibility_posRoot_notEligible() {
        XCTAssertFalse(HandoffEligibility.isEligible(.posRoot(tenantSlug: "acme")))
    }

    func test_eligibility_posNewCart_notEligible() {
        XCTAssertFalse(HandoffEligibility.isEligible(.posNewCart(tenantSlug: "acme")))
    }

    func test_eligibility_posReturn_notEligible() {
        XCTAssertFalse(HandoffEligibility.isEligible(.posReturn(tenantSlug: "acme")))
    }

    func test_eligibility_settings_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(.settings(tenantSlug: "acme", section: nil))
        )
    }

    func test_eligibility_auditLogs_notEligible() {
        XCTAssertFalse(HandoffEligibility.isEligible(.auditLogs(tenantSlug: "acme")))
    }

    func test_eligibility_smsThread_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(
                .smsThread(tenantSlug: "acme", phone: "+14155550100")
            )
        )
    }

    func test_eligibility_search_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(.search(tenantSlug: "acme", query: "x"))
        )
    }

    func test_eligibility_timeclock_notEligible() {
        XCTAssertFalse(HandoffEligibility.isEligible(.timeclock(tenantSlug: "acme")))
    }

    func test_eligibility_notifications_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(.notifications(tenantSlug: "acme"))
        )
    }

    func test_eligibility_reports_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(.reports(tenantSlug: "acme", name: "rev"))
        )
    }

    func test_eligibility_magicLink_notEligible() {
        XCTAssertFalse(
            HandoffEligibility.isEligible(
                .magicLink(tenantSlug: "acme", token: "tok12345678")
            )
        )
    }

    func test_eligibility_activityType_ticket_returnsCaseTicketDetail() {
        let t = HandoffEligibility.activityType(
            for: .ticket(tenantSlug: "acme", id: "T-1")
        )
        XCTAssertEqual(t, .ticketDetail)
    }

    func test_eligibility_activityType_dashboard_returnsNil() {
        let t = HandoffEligibility.activityType(
            for: .dashboard(tenantSlug: "acme")
        )
        XCTAssertNil(t)
    }

    // MARK: Rejection reasons

    func test_eligibility_rejectionReason_eligibleDestination_returnsNil() {
        let reason = HandoffEligibility.rejectionReason(
            for: .ticket(tenantSlug: "acme", id: "T-1")
        )
        XCTAssertNil(reason)
    }

    func test_eligibility_rejectionReason_magicLink_containsToken() {
        let reason = HandoffEligibility.rejectionReason(
            for: .magicLink(tenantSlug: "acme", token: "tok12345678")
        )
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.lowercased().contains("token") ||
                      reason!.lowercased().contains("auth"),
                      "Rejection reason should mention token or auth")
    }

    func test_eligibility_rejectionReason_posCart_containsPOS() {
        let reason = HandoffEligibility.rejectionReason(for: .posNewCart(tenantSlug: "acme"))
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.lowercased().contains("pos") ||
                      reason!.lowercased().contains("cart"),
                      "Rejection reason should mention POS or cart")
    }

    func test_eligibility_rejectionReason_smsThread_isMeaningful() {
        let reason = HandoffEligibility.rejectionReason(
            for: .smsThread(tenantSlug: "acme", phone: "+1")
        )
        XCTAssertNotNil(reason)
        XCTAssertFalse(reason!.isEmpty)
    }

    // =========================================================================
    // MARK: - 4. HandoffBuilder
    // =========================================================================

    func test_builder_ticket_returnsActivity() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-99")
        )
        XCTAssertNotNil(activity)
    }

    func test_builder_ticket_activityType() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-99")
        )
        XCTAssertEqual(
            activity?.activityType,
            HandoffActivityType.ticketDetail.activityTypeIdentifier
        )
    }

    func test_builder_ticket_isEligibleForHandoff() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-99")
        )
        XCTAssertEqual(activity?.isEligibleForHandoff, true)
    }

    func test_builder_ticket_isEligibleForSearch() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-99")
        )
        XCTAssertEqual(activity?.isEligibleForSearch, true)
    }

    func test_builder_ticket_webpageURL_containsSlugAndId() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-99")
        )
        let urlString = activity?.webpageURL?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("acme"), "URL must contain the tenant slug")
        XCTAssertTrue(urlString.contains("T-99"), "URL must contain the ticket ID")
        XCTAssertTrue(urlString.contains("tickets"), "URL must contain the resource segment")
    }

    func test_builder_ticket_webpageURL_isHTTPS() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-1")
        )
        XCTAssertEqual(activity?.webpageURL?.scheme, "https")
    }

    func test_builder_ticket_userInfo_containsTenantSlug() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-5")
        )
        let info = activity?.userInfo as? [String: String]
        XCTAssertEqual(info?[HandoffBuilder.Keys.tenantSlug], "acme")
    }

    func test_builder_ticket_userInfo_containsDestinationURL() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-5")
        )
        let info = activity?.userInfo as? [String: String]
        let urlString = info?[HandoffBuilder.Keys.destinationURL]
        XCTAssertNotNil(urlString)
        XCTAssertTrue(urlString!.contains("tickets/T-5"))
    }

    func test_builder_ticket_title_containsId() {
        let activity = HandoffBuilder.build(
            from: .ticket(tenantSlug: "acme", id: "T-42")
        )
        XCTAssertTrue(activity?.title?.contains("T-42") == true)
    }

    func test_builder_customer_activityType() {
        let activity = HandoffBuilder.build(
            from: .customer(tenantSlug: "acme", id: "C-7")
        )
        XCTAssertEqual(
            activity?.activityType,
            HandoffActivityType.customerDetail.activityTypeIdentifier
        )
    }

    func test_builder_invoice_activityType() {
        let activity = HandoffBuilder.build(
            from: .invoice(tenantSlug: "acme", id: "INV-1")
        )
        XCTAssertEqual(
            activity?.activityType,
            HandoffActivityType.invoiceDetail.activityTypeIdentifier
        )
    }

    func test_builder_estimate_activityType() {
        let activity = HandoffBuilder.build(
            from: .estimate(tenantSlug: "acme", id: "EST-3")
        )
        XCTAssertEqual(
            activity?.activityType,
            HandoffActivityType.estimateDetail.activityTypeIdentifier
        )
    }

    func test_builder_ineligibleDestination_returnsNil() {
        // Dashboard is not Handoff-eligible
        XCTAssertNil(HandoffBuilder.build(from: .dashboard(tenantSlug: "acme")))
    }

    func test_builder_posRoot_returnsNil() {
        XCTAssertNil(HandoffBuilder.build(from: .posRoot(tenantSlug: "acme")))
    }

    func test_builder_magicLink_returnsNil() {
        XCTAssertNil(
            HandoffBuilder.build(
                from: .magicLink(tenantSlug: "acme", token: "tok12345678")
            )
        )
    }

    func test_builder_settings_returnsNil() {
        XCTAssertNil(
            HandoffBuilder.build(
                from: .settings(tenantSlug: "acme", section: nil)
            )
        )
    }

    // =========================================================================
    // MARK: - 5. HandoffParser – round-trips via userInfo
    // =========================================================================

    func test_parser_roundTrip_ticket() {
        roundTrip(.ticket(tenantSlug: "acme", id: "T-001"))
    }

    func test_parser_roundTrip_customer() {
        roundTrip(.customer(tenantSlug: "acme", id: "C-42"))
    }

    func test_parser_roundTrip_invoice() {
        roundTrip(.invoice(tenantSlug: "acme", id: "INV-9"))
    }

    func test_parser_roundTrip_estimate() {
        roundTrip(.estimate(tenantSlug: "acme", id: "EST-7"))
    }

    // =========================================================================
    // MARK: - 6. HandoffParser – webpageURL fallback
    // =========================================================================

    func test_parser_fallback_webpageURL_ticket() {
        // Simulate an activity from an older app version that only sets webpageURL.
        let url = URL(string: "https://app.bizarrecrm.com/acme/tickets/T-99")!
        let activity = NSUserActivity(
            activityType: HandoffActivityType.ticketDetail.activityTypeIdentifier
        )
        activity.webpageURL = url

        let parsed = HandoffParser.destination(from: activity)
        XCTAssertEqual(parsed, .ticket(tenantSlug: "acme", id: "T-99"))
    }

    func test_parser_fallback_webpageURL_invoice() {
        let url = URL(string: "https://app.bizarrecrm.com/acme/invoices/INV-3")!
        let activity = NSUserActivity(
            activityType: HandoffActivityType.invoiceDetail.activityTypeIdentifier
        )
        activity.webpageURL = url

        let parsed = HandoffParser.destination(from: activity)
        XCTAssertEqual(parsed, .invoice(tenantSlug: "acme", id: "INV-3"))
    }

    func test_parser_unknownActivity_returnsNil() {
        let activity = NSUserActivity(activityType: "com.example.unknown")
        XCTAssertNil(HandoffParser.destination(from: activity))
    }

    func test_parser_malformedUserInfo_fallsBackToWebpageURL() {
        // userInfo has a bad URL but webpageURL is valid.
        let webURL = URL(string: "https://app.bizarrecrm.com/acme/tickets/T-5")!
        let activity = NSUserActivity(
            activityType: HandoffActivityType.ticketDetail.activityTypeIdentifier
        )
        activity.userInfo = [HandoffBuilder.Keys.destinationURL: "not-a-url"]
        activity.webpageURL = webURL

        let parsed = HandoffParser.destination(from: activity)
        XCTAssertEqual(parsed, .ticket(tenantSlug: "acme", id: "T-5"))
    }

    func test_parser_noUserInfoNoWebpage_returnsNil() {
        let activity = NSUserActivity(
            activityType: HandoffActivityType.ticketDetail.activityTypeIdentifier
        )
        XCTAssertNil(HandoffParser.destination(from: activity))
    }

    // MARK: eligibleDestination guard

    func test_parser_eligibleDestination_ticket_returnsDest() {
        let url = URL(string: "https://app.bizarrecrm.com/acme/tickets/T-1")!
        let activity = NSUserActivity(
            activityType: HandoffActivityType.ticketDetail.activityTypeIdentifier
        )
        activity.webpageURL = url

        let result = HandoffParser.eligibleDestination(from: activity)
        XCTAssertEqual(result, .ticket(tenantSlug: "acme", id: "T-1"))
    }

    func test_parser_eligibleDestination_dashboard_returnsNil() {
        // Manually craft a webpageURL for a dashboard destination.
        let url = URL(string: "https://app.bizarrecrm.com/acme/dashboard")!
        let activity = NSUserActivity(activityType: "com.bizarrecrm.dashboard")
        activity.webpageURL = url

        let result = HandoffParser.eligibleDestination(from: activity)
        XCTAssertNil(result, "Dashboard is not Handoff-eligible and must be filtered out")
    }

    // =========================================================================
    // MARK: - 7. ClipboardBridge.copy return values
    // =========================================================================

    func test_clipboard_ticket_returnsCopied() {
        let result = ClipboardBridge.copy(.ticket(tenantSlug: "acme", id: "T-77"))
        if case .copied(let text) = result {
            XCTAssertEqual(text, "T-77")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_customer_returnsCopied() {
        let result = ClipboardBridge.copy(.customer(tenantSlug: "acme", id: "C-5"))
        if case .copied(let text) = result {
            XCTAssertEqual(text, "C-5")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_invoice_returnsCopied() {
        let result = ClipboardBridge.copy(.invoice(tenantSlug: "acme", id: "INV-2"))
        if case .copied(let text) = result {
            XCTAssertEqual(text, "INV-2")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_estimate_returnsCopied() {
        let result = ClipboardBridge.copy(.estimate(tenantSlug: "acme", id: "EST-4"))
        if case .copied(let text) = result {
            XCTAssertEqual(text, "EST-4")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_lead_returnsCopied() {
        let result = ClipboardBridge.copy(.lead(tenantSlug: "acme", id: "L-3"))
        if case .copied(let text) = result {
            XCTAssertEqual(text, "L-3")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_appointment_returnsCopied() {
        let result = ClipboardBridge.copy(
            .appointment(tenantSlug: "acme", id: "APT-9")
        )
        if case .copied(let text) = result {
            XCTAssertEqual(text, "APT-9")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_inventory_returnsCopiedSku() {
        let result = ClipboardBridge.copy(.inventory(tenantSlug: "acme", sku: "SKU-88"))
        if case .copied(let text) = result {
            XCTAssertEqual(text, "SKU-88")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_smsThread_returnsCopiedPhone() {
        let result = ClipboardBridge.copy(
            .smsThread(tenantSlug: "acme", phone: "+14155550100")
        )
        if case .copied(let text) = result {
            XCTAssertEqual(text, "+14155550100")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_reports_returnsCopiedName() {
        let result = ClipboardBridge.copy(.reports(tenantSlug: "acme", name: "revenue"))
        if case .copied(let text) = result {
            XCTAssertEqual(text, "revenue")
        } else {
            XCTFail("Expected .copied, got \(result)")
        }
    }

    func test_clipboard_dashboard_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.dashboard(tenantSlug: "acme"))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_posRoot_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.posRoot(tenantSlug: "acme"))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_posNewCart_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.posNewCart(tenantSlug: "acme"))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_posReturn_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.posReturn(tenantSlug: "acme"))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_settings_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.settings(tenantSlug: "acme", section: nil))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_auditLogs_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.auditLogs(tenantSlug: "acme"))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_search_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.search(tenantSlug: "acme", query: "x"))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_notifications_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.notifications(tenantSlug: "acme"))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_timeclock_returnsNotApplicable() {
        let result = ClipboardBridge.copy(.timeclock(tenantSlug: "acme"))
        XCTAssertEqual(result, .notApplicable)
    }

    func test_clipboard_magicLink_returnsNotApplicable() {
        let result = ClipboardBridge.copy(
            .magicLink(tenantSlug: "acme", token: "tok12345678")
        )
        XCTAssertEqual(result, .notApplicable)
    }

    // =========================================================================
    // MARK: - 8. CopyResult equatable
    // =========================================================================

    func test_copyResult_equatable_copiedEqual() {
        let a = ClipboardBridge.CopyResult.copied(plainText: "T-1")
        let b = ClipboardBridge.CopyResult.copied(plainText: "T-1")
        XCTAssertEqual(a, b)
    }

    func test_copyResult_equatable_copiedNotEqual() {
        let a = ClipboardBridge.CopyResult.copied(plainText: "T-1")
        let b = ClipboardBridge.CopyResult.copied(plainText: "T-2")
        XCTAssertNotEqual(a, b)
    }

    func test_copyResult_equatable_notApplicableEqual() {
        XCTAssertEqual(
            ClipboardBridge.CopyResult.notApplicable,
            ClipboardBridge.CopyResult.notApplicable
        )
    }

    func test_copyResult_equatable_differentCasesNotEqual() {
        let a = ClipboardBridge.CopyResult.copied(plainText: "T-1")
        let b = ClipboardBridge.CopyResult.notApplicable
        XCTAssertNotEqual(a, b)
    }
}
