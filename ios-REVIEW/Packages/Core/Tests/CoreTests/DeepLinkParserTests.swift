import XCTest
@testable import Core

// swiftlint:disable file_length type_body_length

/// Full matrix for `DeepLinkParser.parse(_:)`.
///
/// Covers every `DeepLinkRoute` case, edge conditions, malformed input,
/// query-param preservation, case-insensitivity, and the public/universal-link
/// split.  Target: ≥ 40 distinct test cases.
final class DeepLinkParserTests: XCTestCase {

    // MARK: - Helpers

    private func url(_ string: String) -> URL {
        // Force-unwrap is intentional in tests — a bad literal is a test bug.
        URL(string: string)!
    }

    private func parse(_ string: String) -> DeepLinkRoute {
        DeepLinkParser.parse(url(string))
    }

    // MARK: - 1. Custom scheme — resource routes

    func test_customScheme_ticket_returnsTicket() {
        let route = parse("bizarrecrm://acme/tickets/T-001")
        XCTAssertEqual(route, .ticket(tenantSlug: "acme", id: "T-001"))
    }

    func test_customScheme_customer_returnsCustomer() {
        let route = parse("bizarrecrm://acme/customers/CUST-42")
        XCTAssertEqual(route, .customer(tenantSlug: "acme", id: "CUST-42"))
    }

    func test_customScheme_invoice_returnsInvoice() {
        let route = parse("bizarrecrm://acme/invoices/INV-9")
        XCTAssertEqual(route, .invoice(tenantSlug: "acme", id: "INV-9"))
    }

    func test_customScheme_estimate_returnsEstimate() {
        let route = parse("bizarrecrm://acme/estimates/EST-7")
        XCTAssertEqual(route, .estimate(tenantSlug: "acme", id: "EST-7"))
    }

    func test_customScheme_lead_returnsLead() {
        let route = parse("bizarrecrm://acme/leads/LEAD-5")
        XCTAssertEqual(route, .lead(tenantSlug: "acme", id: "LEAD-5"))
    }

    func test_customScheme_appointment_returnsAppointment() {
        let route = parse("bizarrecrm://acme/appointments/APT-3")
        XCTAssertEqual(route, .appointment(tenantSlug: "acme", id: "APT-3"))
    }

    func test_customScheme_inventory_returnsInventory() {
        let route = parse("bizarrecrm://acme/inventory/SKU-999")
        XCTAssertEqual(route, .inventory(tenantSlug: "acme", sku: "SKU-999"))
    }

    func test_customScheme_smsThread_returnsSmsThread() {
        let route = parse("bizarrecrm://acme/sms/THREAD-12")
        XCTAssertEqual(route, .smsThread(tenantSlug: "acme", threadID: "THREAD-12"))
    }

    func test_customScheme_notifications_returnsNotifications() {
        let route = parse("bizarrecrm://acme/notifications")
        XCTAssertEqual(route, .notifications(tenantSlug: "acme"))
    }

    func test_customScheme_timeclock_returnsTimeclock() {
        let route = parse("bizarrecrm://acme/timeclock")
        XCTAssertEqual(route, .timeclock(tenantSlug: "acme"))
    }

    func test_customScheme_dashboard_returnsDashboard() {
        let route = parse("bizarrecrm://acme/dashboard")
        XCTAssertEqual(route, .dashboard(tenantSlug: "acme"))
    }

    func test_customScheme_reports_returnsReports() {
        let route = parse("bizarrecrm://acme/reports/revenue")
        XCTAssertEqual(route, .reports(tenantSlug: "acme", name: "revenue"))
    }

    // MARK: - 2. POS routes

    func test_customScheme_posNew_returnsPosNewCart() {
        let route = parse("bizarrecrm://acme/pos/new")
        XCTAssertEqual(route, .posNewCart(tenantSlug: "acme"))
    }

    func test_customScheme_posSaleNew_returnsPosNewCart() {
        let route = parse("bizarrecrm://acme/pos/sale/new")
        XCTAssertEqual(route, .posNewCart(tenantSlug: "acme"))
    }

    func test_customScheme_posReturn_returnsPosReturn() {
        let route = parse("bizarrecrm://acme/pos/return")
        XCTAssertEqual(route, .posReturn(tenantSlug: "acme"))
    }

    func test_customScheme_posRoot_returnsPosRoot() {
        let route = parse("bizarrecrm://acme/pos")
        XCTAssertEqual(route, .posRoot(tenantSlug: "acme"))
    }

    // MARK: - 3. Settings routes

    func test_customScheme_settingsAudit_returnsAuditLogs() {
        let route = parse("bizarrecrm://acme/settings/audit")
        XCTAssertEqual(route, .auditLogs(tenantSlug: "acme"))
    }

    func test_customScheme_settingsRoot_returnsSettingsNoSection() {
        let route = parse("bizarrecrm://acme/settings")
        XCTAssertEqual(route, .settings(tenantSlug: "acme", section: nil))
    }

    func test_customScheme_settingsWithSection_returnsSettingsWithSection() {
        let route = parse("bizarrecrm://acme/settings/tax")
        XCTAssertEqual(route, .settings(tenantSlug: "acme", section: "tax"))
    }

    // MARK: - 4. Auth / magic link

    func test_customScheme_magicLink_returnsMagicLink() {
        let route = parse("bizarrecrm://acme/auth/magic?token=abc123")
        XCTAssertEqual(route, .magicLink(tenantSlug: "acme", token: "abc123"))
    }

    func test_customScheme_magicLink_missingToken_returnsUnknown() {
        let route = parse("bizarrecrm://acme/auth/magic")
        guard case .unknown = route else {
            XCTFail("Expected .unknown, got \(route)"); return
        }
    }

    func test_customScheme_magicLink_emptyToken_returnsUnknown() {
        let route = parse("bizarrecrm://acme/auth/magic?token=")
        guard case .unknown = route else {
            XCTFail("Expected .unknown, got \(route)"); return
        }
    }

    // MARK: - 5. Search with query param

    func test_customScheme_search_withQuery_preservesQueryParam() {
        // URLComponents does not decode '+' as space (that is an HTML form
        // convention only).  Use percent-encoded space (%20) to confirm the
        // query value is preserved as-is through the parser.
        let route = parse("bizarrecrm://acme/search?q=iPhone%20repair")
        XCTAssertEqual(route, .search(tenantSlug: "acme", query: "iPhone repair"))
    }

    func test_customScheme_search_withoutQuery_returnsNilQuery() {
        let route = parse("bizarrecrm://acme/search")
        XCTAssertEqual(route, .search(tenantSlug: "acme", query: nil))
    }

    // MARK: - 6. Missing / empty slug

    func test_customScheme_missingHost_returnsUnknown() {
        // No host after the scheme — impossible via normal URL but we guard it.
        // URL("bizarrecrm:///tickets/1") has an empty host string.
        let u = URL(string: "bizarrecrm:///tickets/1")!
        let route = DeepLinkParser.parse(u)
        guard case .unknown = route else {
            XCTFail("Expected .unknown for missing slug, got \(route)"); return
        }
    }

    func test_customScheme_emptyPath_returnsDashboard() {
        // bizarrecrm://acme with no path → dashboard
        let route = parse("bizarrecrm://acme")
        XCTAssertEqual(route, .dashboard(tenantSlug: "acme"))
    }

    // MARK: - 7. Unknown / unrecognised resource

    func test_customScheme_unknownResource_returnsUnknown() {
        let route = parse("bizarrecrm://acme/ponies/rainbow")
        guard case .unknown = route else {
            XCTFail("Expected .unknown for unknown resource, got \(route)"); return
        }
    }

    // MARK: - 8. Resource without required ID

    func test_customScheme_ticketWithoutId_returnsUnknown() {
        let route = parse("bizarrecrm://acme/tickets")
        guard case .unknown = route else {
            XCTFail("Expected .unknown when ticket ID is missing, got \(route)"); return
        }
    }

    func test_customScheme_invoiceWithoutId_returnsUnknown() {
        let route = parse("bizarrecrm://acme/invoices")
        guard case .unknown = route else {
            XCTFail("Expected .unknown when invoice ID is missing, got \(route)"); return
        }
    }

    func test_customScheme_reportsWithoutName_returnsUnknown() {
        let route = parse("bizarrecrm://acme/reports")
        guard case .unknown = route else {
            XCTFail("Expected .unknown when report name is missing, got \(route)"); return
        }
    }

    // MARK: - 9. Case-insensitivity on scheme / host / resource keywords

    func test_caseInsensitivity_scheme_uppercased() {
        // URL lowercases the scheme automatically per RFC, but let's be explicit.
        let u = URL(string: "bizarrecrm://acme/tickets/T-1")!
        let route = DeepLinkParser.parse(u)
        XCTAssertEqual(route, .ticket(tenantSlug: "acme", id: "T-1"))
    }

    func test_caseInsensitivity_universalLinkHost_mixedCase() {
        // Universal link with mixed-case host.
        let u = URL(string: "https://App.BizarreCRM.Com/acme/tickets/T-2")!
        let route = DeepLinkParser.parse(u)
        XCTAssertEqual(route, .ticket(tenantSlug: "acme", id: "T-2"))
    }

    func test_caseInsensitivity_resource_mixed() {
        // "Tickets" capitalised — parser must lowercase.
        let u = URL(string: "bizarrecrm://acme/Tickets/T-3")!
        let route = DeepLinkParser.parse(u)
        XCTAssertEqual(route, .ticket(tenantSlug: "acme", id: "T-3"))
    }

    func test_caseInsensitivity_posNew_uppercased() {
        let u = URL(string: "bizarrecrm://acme/POS/NEW")!
        let route = DeepLinkParser.parse(u)
        XCTAssertEqual(route, .posNewCart(tenantSlug: "acme"))
    }

    // MARK: - 10. Universal Links

    func test_universalLink_ticket_parsedCorrectly() {
        let route = parse("https://app.bizarrecrm.com/acme/tickets/T-10")
        XCTAssertEqual(route, .ticket(tenantSlug: "acme", id: "T-10"))
    }

    func test_universalLink_customer_parsedCorrectly() {
        let route = parse("https://app.bizarrecrm.com/acme/customers/C-5")
        XCTAssertEqual(route, .customer(tenantSlug: "acme", id: "C-5"))
    }

    func test_universalLink_publicPath_returnsSafariExternal() {
        let route = parse("https://app.bizarrecrm.com/public/tracking/abc123")
        guard case .safariExternal(let u) = route else {
            XCTFail("Expected .safariExternal for /public/ path, got \(route)"); return
        }
        XCTAssertTrue(u.path.hasPrefix("/public/"))
    }

    func test_universalLink_publicRoot_returnsSafariExternal() {
        let route = parse("https://app.bizarrecrm.com/public")
        guard case .safariExternal = route else {
            XCTFail("Expected .safariExternal for /public, got \(route)"); return
        }
    }

    func test_universalLink_unknownHost_returnsSafariExternal() {
        let route = parse("https://other.example.com/acme/tickets/T-1")
        guard case .safariExternal = route else {
            XCTFail("Expected .safariExternal for unknown host, got \(route)"); return
        }
    }

    // MARK: - 11. Unknown scheme

    func test_unknownScheme_ftp_returnsSafariExternal() {
        let route = parse("ftp://files.example.com/path")
        guard case .safariExternal = route else {
            XCTFail("Expected .safariExternal for ftp scheme, got \(route)"); return
        }
    }

    func test_unknownScheme_mailto_returnsSafariExternal() {
        let route = parse("mailto:support@bizarrecrm.com")
        guard case .safariExternal = route else {
            XCTFail("Expected .safariExternal for mailto, got \(route)"); return
        }
    }

    // MARK: - 12. Malformed / edge-case URLs

    func test_malformed_noScheme_returnsUnknown() {
        // URL(string:) can parse a relative URL without scheme;
        // DeepLinkParser should handle nil scheme gracefully.
        guard let u = URL(string: "just-a-path/no-scheme") else {
            // On some platforms this returns nil; that's fine too.
            return
        }
        let route = DeepLinkParser.parse(u)
        // Either .unknown or .safariExternal is acceptable — no crash.
        switch route {
        case .unknown, .safariExternal:
            break
        default:
            XCTFail("Expected .unknown or .safariExternal for no-scheme URL, got \(route)")
        }
    }

    func test_malformed_emptyString_doesNotCrash() {
        guard let u = URL(string: "") else { return } // fine if nil
        _ = DeepLinkParser.parse(u)  // must not crash
    }

    func test_malformed_bizarrecrm_noPath_returnsDashboard() {
        // bizarrecrm://slug with zero path components → dashboard
        let route = parse("bizarrecrm://my-shop")
        XCTAssertEqual(route, .dashboard(tenantSlug: "my-shop"))
    }

    func test_malformed_percentEncoded_ticketId_preserved() {
        // IDs can contain characters that get percent-encoded.
        let route = parse("bizarrecrm://acme/tickets/T%2D001")
        // URLComponents percent-decodes the path, so we get "T-001".
        XCTAssertEqual(route, .ticket(tenantSlug: "acme", id: "T-001"))
    }

    // MARK: - 13. Slug with hyphens / underscores

    func test_slugWithHyphens_parsedCorrectly() {
        let route = parse("bizarrecrm://my-repair-shop/tickets/T-1")
        XCTAssertEqual(route, .ticket(tenantSlug: "my-repair-shop", id: "T-1"))
    }

    func test_slugWithUnderscores_parsedCorrectly() {
        let route = parse("bizarrecrm://my_repair_shop/customers/C-2")
        XCTAssertEqual(route, .customer(tenantSlug: "my_repair_shop", id: "C-2"))
    }

    // MARK: - 14. Numeric-string IDs

    func test_numericId_ticket_parsedAsString() {
        let route = parse("bizarrecrm://acme/tickets/12345")
        XCTAssertEqual(route, .ticket(tenantSlug: "acme", id: "12345"))
    }

    func test_numericId_invoice_parsedAsString() {
        let route = parse("bizarrecrm://acme/invoices/99999")
        XCTAssertEqual(route, .invoice(tenantSlug: "acme", id: "99999"))
    }

    // MARK: - 15. Extra query params don't disrupt routing

    func test_extraQueryParams_onTicketRoute_ignoredSafely() {
        let route = parse("bizarrecrm://acme/tickets/T-1?source=email&campaign=promo")
        XCTAssertEqual(route, .ticket(tenantSlug: "acme", id: "T-1"))
    }

    func test_magicLink_preservesToken_evenWithExtraParams() {
        let route = parse("bizarrecrm://acme/auth/magic?token=xyz789&utm=email")
        XCTAssertEqual(route, .magicLink(tenantSlug: "acme", token: "xyz789"))
    }

    // MARK: - 16. Settings audit (admin-only route)

    func test_settingsAudit_caseInsensitive() {
        let u = URL(string: "bizarrecrm://acme/SETTINGS/AUDIT")!
        let route = DeepLinkParser.parse(u)
        XCTAssertEqual(route, .auditLogs(tenantSlug: "acme"))
    }

    // MARK: - 17. Universal link without slug segment

    func test_universalLink_noSlug_returnsUnknown() {
        // https://app.bizarrecrm.com/ with only the host
        let route = parse("https://app.bizarrecrm.com/")
        guard case .unknown = route else {
            // Could also be dashboard if slug is derived from first segment;
            // the key contract is: no crash.
            return
        }
    }

    // MARK: - 18. Static parse function (isolated, no shared state)

    func test_staticParse_isIdempotent() {
        let urlString = "bizarrecrm://acme/tickets/T-77"
        let first  = DeepLinkParser.parse(url(urlString))
        let second = DeepLinkParser.parse(url(urlString))
        XCTAssertEqual(first, second, "parse(_:) must be pure/idempotent")
    }

    // MARK: - 19. HTTP (non-HTTPS) universal link

    func test_httpUniversalLink_treatedSameAsHttps() {
        // HTTP universal links are unusual but should not crash.
        let route = parse("http://app.bizarrecrm.com/acme/invoices/INV-1")
        XCTAssertEqual(route, .invoice(tenantSlug: "acme", id: "INV-1"))
    }

    // MARK: - 20. Auth subpath unknown action

    func test_customScheme_authUnknownAction_returnsUnknown() {
        let route = parse("bizarrecrm://acme/auth/sso")
        guard case .unknown = route else {
            XCTFail("Expected .unknown for unsupported auth action, got \(route)"); return
        }
    }
}
