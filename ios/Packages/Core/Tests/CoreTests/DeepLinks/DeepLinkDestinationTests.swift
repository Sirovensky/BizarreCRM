import XCTest
@testable import Core

// MARK: - DeepLinkDestinationTests

/// Tests `DeepLinkDestination`, `DeepLinkURLParser`, `DeepLinkBuilder`,
/// and `DeepLinkValidator`.
///
/// Coverage targets:
/// - Every `DeepLinkDestination` case parsed from both URL forms.
/// - Round-trip: parse → build → parse yields the same destination.
/// - Invalid / injection URL strings are rejected.
/// - Validator rejects open-redirect hosts, path traversal, null bytes, etc.

// swiftlint:disable file_length type_body_length
final class DeepLinkDestinationTests: XCTestCase {

    // MARK: - Helpers

    private func url(_ s: String) -> URL { URL(string: s)! }

    private func parseCustom(_ s: String) -> DeepLinkDestination? {
        DeepLinkURLParser.parse(url(s))
    }

    private func parseUniversal(_ path: String) -> DeepLinkDestination? {
        DeepLinkURLParser.parse(url("https://\(DeepLinkURLParser.universalLinkHost)\(path)"))
    }

    private func roundTrip(
        _ dest: DeepLinkDestination,
        form: DeepLinkBuilder.Form = .customScheme,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let built = DeepLinkBuilder.build(dest, form: form) else {
            XCTFail("Builder returned nil for \(dest)", file: file, line: line)
            return
        }
        guard let reparsed = DeepLinkURLParser.parse(built) else {
            XCTFail("Parser returned nil for built URL \(built)", file: file, line: line)
            return
        }
        XCTAssertEqual(reparsed, dest, file: file, line: line)
    }

    // =========================================================================
    // MARK: - 1. DeepLinkURLParser – custom scheme
    // =========================================================================

    func test_parser_customScheme_dashboard() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/dashboard"),
                       .dashboard(tenantSlug: "acme"))
    }

    func test_parser_customScheme_emptyPath_returnsDashboard() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme"),
                       .dashboard(tenantSlug: "acme"))
    }

    func test_parser_customScheme_ticket() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/tickets/T-001"),
                       .ticket(tenantSlug: "acme", id: "T-001"))
    }

    func test_parser_customScheme_customer() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/customers/C-42"),
                       .customer(tenantSlug: "acme", id: "C-42"))
    }

    func test_parser_customScheme_invoice() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/invoices/INV-9"),
                       .invoice(tenantSlug: "acme", id: "INV-9"))
    }

    func test_parser_customScheme_estimate() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/estimates/EST-7"),
                       .estimate(tenantSlug: "acme", id: "EST-7"))
    }

    func test_parser_customScheme_lead() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/leads/L-5"),
                       .lead(tenantSlug: "acme", id: "L-5"))
    }

    func test_parser_customScheme_appointment() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/appointments/APT-3"),
                       .appointment(tenantSlug: "acme", id: "APT-3"))
    }

    func test_parser_customScheme_inventory() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/inventory/SKU-999"),
                       .inventory(tenantSlug: "acme", sku: "SKU-999"))
    }

    func test_parser_customScheme_smsThread() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/sms/+14155550100"),
                       .smsThread(tenantSlug: "acme", phone: "+14155550100"))
    }

    func test_parser_customScheme_reports() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/reports/revenue"),
                       .reports(tenantSlug: "acme", name: "revenue"))
    }

    func test_parser_customScheme_posRoot() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/pos"),
                       .posRoot(tenantSlug: "acme"))
    }

    func test_parser_customScheme_posNewCart_viaNew() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/pos/new"),
                       .posNewCart(tenantSlug: "acme"))
    }

    func test_parser_customScheme_posNewCart_viaSaleNew() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/pos/sale/new"),
                       .posNewCart(tenantSlug: "acme"))
    }

    func test_parser_customScheme_posReturn() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/pos/return"),
                       .posReturn(tenantSlug: "acme"))
    }

    func test_parser_customScheme_settingsRoot() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/settings"),
                       .settings(tenantSlug: "acme", section: nil))
    }

    func test_parser_customScheme_settingsSection() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/settings/tax"),
                       .settings(tenantSlug: "acme", section: "tax"))
    }

    func test_parser_customScheme_auditLogs() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/settings/audit"),
                       .auditLogs(tenantSlug: "acme"))
    }

    func test_parser_customScheme_searchWithQuery() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/search?q=iPhone%20repair"),
                       .search(tenantSlug: "acme", query: "iPhone repair"))
    }

    func test_parser_customScheme_searchNoQuery() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/search"),
                       .search(tenantSlug: "acme", query: nil))
    }

    func test_parser_customScheme_notifications() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/notifications"),
                       .notifications(tenantSlug: "acme"))
    }

    func test_parser_customScheme_timeclock() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/timeclock"),
                       .timeclock(tenantSlug: "acme"))
    }

    func test_parser_customScheme_magicLink() {
        XCTAssertEqual(parseCustom("bizarrecrm://acme/auth/magic?token=abc123"),
                       .magicLink(tenantSlug: "acme", token: "abc123"))
    }

    // =========================================================================
    // MARK: - 2. DeepLinkURLParser – universal links
    // =========================================================================

    func test_parser_universal_dashboard() {
        XCTAssertEqual(parseUniversal("/acme/dashboard"),
                       .dashboard(tenantSlug: "acme"))
    }

    func test_parser_universal_ticket() {
        XCTAssertEqual(parseUniversal("/acme/tickets/T-10"),
                       .ticket(tenantSlug: "acme", id: "T-10"))
    }

    func test_parser_universal_customer() {
        XCTAssertEqual(parseUniversal("/acme/customers/C-5"),
                       .customer(tenantSlug: "acme", id: "C-5"))
    }

    func test_parser_universal_invoice() {
        XCTAssertEqual(parseUniversal("/acme/invoices/INV-1"),
                       .invoice(tenantSlug: "acme", id: "INV-1"))
    }

    func test_parser_universal_magicLink() {
        XCTAssertEqual(parseUniversal("/acme/auth/magic?token=XYZ789"),
                       .magicLink(tenantSlug: "acme", token: "XYZ789"))
    }

    func test_parser_universal_publicPath_returnsNil() {
        XCTAssertNil(parseUniversal("/public/tracking/abc123"),
                     "Public paths must not be intercepted")
    }

    func test_parser_universal_publicRoot_returnsNil() {
        XCTAssertNil(parseUniversal("/public"))
    }

    func test_parser_universal_unknownHost_returnsNil() {
        let result = DeepLinkURLParser.parse(url("https://evil.example.com/acme/tickets/T-1"))
        XCTAssertNil(result)
    }

    func test_parser_universal_noSlugSegment_returnsNil() {
        XCTAssertNil(parseUniversal("/"))
    }

    // =========================================================================
    // MARK: - 3. Parser nil cases (invalid input)
    // =========================================================================

    func test_parser_missingHost_returnsNil() {
        let u = URL(string: "bizarrecrm:///tickets/1")!
        XCTAssertNil(DeepLinkURLParser.parse(u))
    }

    func test_parser_unknownScheme_returnsNil() {
        XCTAssertNil(DeepLinkURLParser.parse(url("ftp://files.example.com/path")))
    }

    func test_parser_mailtoScheme_returnsNil() {
        XCTAssertNil(DeepLinkURLParser.parse(url("mailto:support@bizarrecrm.com")))
    }

    func test_parser_ticketMissingId_returnsNil() {
        XCTAssertNil(parseCustom("bizarrecrm://acme/tickets"))
    }

    func test_parser_invoiceMissingId_returnsNil() {
        XCTAssertNil(parseCustom("bizarrecrm://acme/invoices"))
    }

    func test_parser_reportsMissingName_returnsNil() {
        XCTAssertNil(parseCustom("bizarrecrm://acme/reports"))
    }

    func test_parser_smsMissingPhone_returnsNil() {
        XCTAssertNil(parseCustom("bizarrecrm://acme/sms"))
    }

    func test_parser_magicLinkMissingToken_returnsNil() {
        XCTAssertNil(parseCustom("bizarrecrm://acme/auth/magic"))
    }

    func test_parser_magicLinkEmptyToken_returnsNil() {
        XCTAssertNil(parseCustom("bizarrecrm://acme/auth/magic?token="))
    }

    func test_parser_authUnknownAction_returnsNil() {
        XCTAssertNil(parseCustom("bizarrecrm://acme/auth/sso"))
    }

    func test_parser_unknownResource_returnsNil() {
        XCTAssertNil(parseCustom("bizarrecrm://acme/ponies/rainbow"))
    }

    // =========================================================================
    // MARK: - 4. Case-insensitivity
    // =========================================================================

    func test_parser_caseInsensitive_ticketsUppercase() {
        XCTAssertEqual(
            DeepLinkURLParser.parse(url("bizarrecrm://acme/TICKETS/T-3")),
            .ticket(tenantSlug: "acme", id: "T-3")
        )
    }

    func test_parser_caseInsensitive_posNewUppercase() {
        XCTAssertEqual(
            DeepLinkURLParser.parse(url("bizarrecrm://acme/POS/NEW")),
            .posNewCart(tenantSlug: "acme")
        )
    }

    func test_parser_caseInsensitive_universalHostMixedCase() {
        XCTAssertEqual(
            DeepLinkURLParser.parse(url("https://App.BizarreCRM.Com/acme/tickets/T-2")),
            .ticket(tenantSlug: "acme", id: "T-2")
        )
    }

    func test_parser_caseInsensitive_settingsAuditUppercase() {
        XCTAssertEqual(
            DeepLinkURLParser.parse(url("bizarrecrm://acme/SETTINGS/AUDIT")),
            .auditLogs(tenantSlug: "acme")
        )
    }

    // =========================================================================
    // MARK: - 5. Percent-encoding in path
    // =========================================================================

    func test_parser_percentEncodedTicketId_decoded() {
        // T%2D001 decodes to T-001
        XCTAssertEqual(
            parseCustom("bizarrecrm://acme/tickets/T%2D001"),
            .ticket(tenantSlug: "acme", id: "T-001")
        )
    }

    func test_parser_slugWithHyphens() {
        XCTAssertEqual(
            parseCustom("bizarrecrm://my-repair-shop/tickets/T-1"),
            .ticket(tenantSlug: "my-repair-shop", id: "T-1")
        )
    }

    func test_parser_slugWithUnderscores() {
        XCTAssertEqual(
            parseCustom("bizarrecrm://my_shop/customers/C-2"),
            .customer(tenantSlug: "my_shop", id: "C-2")
        )
    }

    // =========================================================================
    // MARK: - 6. Extra query params are silently ignored
    // =========================================================================

    func test_parser_extraQueryParams_onTicket_ignored() {
        XCTAssertEqual(
            parseCustom("bizarrecrm://acme/tickets/T-1?source=email&campaign=promo"),
            .ticket(tenantSlug: "acme", id: "T-1")
        )
    }

    func test_parser_magicLink_extraParams_tokenPreserved() {
        XCTAssertEqual(
            parseCustom("bizarrecrm://acme/auth/magic?token=xyz789&utm=email"),
            .magicLink(tenantSlug: "acme", token: "xyz789")
        )
    }

    // =========================================================================
    // MARK: - 7. DeepLinkBuilder – custom scheme round-trips
    // =========================================================================

    func test_builder_roundTrip_dashboard_customScheme() {
        roundTrip(.dashboard(tenantSlug: "acme"))
    }

    func test_builder_roundTrip_ticket_customScheme() {
        roundTrip(.ticket(tenantSlug: "acme", id: "T-001"))
    }

    func test_builder_roundTrip_customer_customScheme() {
        roundTrip(.customer(tenantSlug: "acme", id: "C-42"))
    }

    func test_builder_roundTrip_invoice_customScheme() {
        roundTrip(.invoice(tenantSlug: "acme", id: "INV-9"))
    }

    func test_builder_roundTrip_estimate_customScheme() {
        roundTrip(.estimate(tenantSlug: "acme", id: "EST-7"))
    }

    func test_builder_roundTrip_lead_customScheme() {
        roundTrip(.lead(tenantSlug: "acme", id: "L-5"))
    }

    func test_builder_roundTrip_appointment_customScheme() {
        roundTrip(.appointment(tenantSlug: "acme", id: "APT-3"))
    }

    func test_builder_roundTrip_inventory_customScheme() {
        roundTrip(.inventory(tenantSlug: "acme", sku: "SKU-999"))
    }

    func test_builder_roundTrip_smsThread_customScheme() {
        roundTrip(.smsThread(tenantSlug: "acme", phone: "+14155550100"))
    }

    func test_builder_roundTrip_reports_customScheme() {
        roundTrip(.reports(tenantSlug: "acme", name: "revenue"))
    }

    func test_builder_roundTrip_posRoot_customScheme() {
        roundTrip(.posRoot(tenantSlug: "acme"))
    }

    func test_builder_roundTrip_posNewCart_customScheme() {
        roundTrip(.posNewCart(tenantSlug: "acme"))
    }

    func test_builder_roundTrip_posReturn_customScheme() {
        roundTrip(.posReturn(tenantSlug: "acme"))
    }

    func test_builder_roundTrip_settingsRoot_customScheme() {
        roundTrip(.settings(tenantSlug: "acme", section: nil))
    }

    func test_builder_roundTrip_settingsSection_customScheme() {
        roundTrip(.settings(tenantSlug: "acme", section: "tax"))
    }

    func test_builder_roundTrip_auditLogs_customScheme() {
        roundTrip(.auditLogs(tenantSlug: "acme"))
    }

    func test_builder_roundTrip_searchWithQuery_customScheme() {
        roundTrip(.search(tenantSlug: "acme", query: "iPhone repair"))
    }

    func test_builder_roundTrip_searchNoQuery_customScheme() {
        roundTrip(.search(tenantSlug: "acme", query: nil))
    }

    func test_builder_roundTrip_notifications_customScheme() {
        roundTrip(.notifications(tenantSlug: "acme"))
    }

    func test_builder_roundTrip_timeclock_customScheme() {
        roundTrip(.timeclock(tenantSlug: "acme"))
    }

    func test_builder_roundTrip_magicLink_customScheme() {
        roundTrip(.magicLink(tenantSlug: "acme", token: "abc12345"))
    }

    // =========================================================================
    // MARK: - 8. DeepLinkBuilder – universal-link round-trips
    // =========================================================================

    func test_builder_roundTrip_ticket_universalLink() {
        roundTrip(.ticket(tenantSlug: "acme", id: "T-001"), form: .universalLink)
    }

    func test_builder_roundTrip_invoice_universalLink() {
        roundTrip(.invoice(tenantSlug: "acme", id: "INV-9"), form: .universalLink)
    }

    func test_builder_roundTrip_magicLink_universalLink() {
        roundTrip(.magicLink(tenantSlug: "acme", token: "abc12345"), form: .universalLink)
    }

    func test_builder_roundTrip_posNewCart_universalLink() {
        roundTrip(.posNewCart(tenantSlug: "acme"), form: .universalLink)
    }

    func test_builder_roundTrip_search_universalLink() {
        roundTrip(.search(tenantSlug: "acme", query: "widget"), form: .universalLink)
    }

    // MARK: Builder produces correct scheme

    func test_builder_customScheme_urlHasCorrectScheme() {
        let url = DeepLinkBuilder.build(.dashboard(tenantSlug: "acme"), form: .customScheme)
        XCTAssertEqual(url?.scheme, "bizarrecrm")
    }

    func test_builder_universalLink_urlHasHttpsScheme() {
        let url = DeepLinkBuilder.build(.dashboard(tenantSlug: "acme"), form: .universalLink)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, DeepLinkURLParser.universalLinkHost)
    }

    // =========================================================================
    // MARK: - 9. DeepLinkValidator – URL-layer checks
    // =========================================================================

    func test_validator_validCustomScheme_isValid() {
        let result = DeepLinkValidator.validate(url: url("bizarrecrm://acme/tickets/T-1"))
        XCTAssertTrue(result.isValid)
    }

    func test_validator_validUniversalLink_isValid() {
        let result = DeepLinkValidator.validate(
            url: url("https://app.bizarrecrm.com/acme/tickets/T-1")
        )
        XCTAssertTrue(result.isValid)
    }

    func test_validator_unknownHost_isInvalid() {
        let result = DeepLinkValidator.validate(
            url: url("https://evil.example.com/acme/tickets/T-1")
        )
        XCTAssertFalse(result.isValid)
        if case .invalid(let reason) = result {
            XCTAssertTrue(reason.contains("not in the allowed list"))
        }
    }

    func test_validator_unknownScheme_isInvalid() {
        let result = DeepLinkValidator.validate(url: url("ftp://acme/tickets/T-1"))
        XCTAssertFalse(result.isValid)
    }

    func test_validator_pathTraversal_dotDot_isInvalid() {
        // Path traversal: /../ segments
        let u = URL(string: "bizarrecrm://acme/tickets/../../../etc/passwd")!
        let result = DeepLinkValidator.validate(url: u)
        XCTAssertFalse(result.isValid, "Path traversal must be rejected")
    }

    func test_validator_nullByte_isInvalid() {
        // Null byte injection
        guard let u = URL(string: "bizarrecrm://acme/tickets/T-\0-1") else {
            // URL construction fails on some platforms — that's fine
            return
        }
        let result = DeepLinkValidator.validate(url: u)
        XCTAssertFalse(result.isValid)
    }

    func test_validator_tooLongURL_isInvalid() {
        let longID = String(repeating: "x", count: 2_100)
        guard let u = URL(string: "bizarrecrm://acme/tickets/\(longID)") else { return }
        let result = DeepLinkValidator.validate(url: u)
        XCTAssertFalse(result.isValid)
    }

    func test_validator_httpScheme_validHost_isValid() {
        let result = DeepLinkValidator.validate(
            url: url("http://app.bizarrecrm.com/acme/invoices/INV-1")
        )
        XCTAssertTrue(result.isValid)
    }

    // =========================================================================
    // MARK: - 10. DeepLinkValidator – destination-layer checks
    // =========================================================================

    func test_validator_destination_validTicket_isValid() {
        let result = DeepLinkValidator.validate(
            destination: .ticket(tenantSlug: "acme", id: "T-001")
        )
        XCTAssertTrue(result.isValid)
    }

    func test_validator_destination_emptySlug_isInvalid() {
        let result = DeepLinkValidator.validate(
            destination: .dashboard(tenantSlug: "")
        )
        XCTAssertFalse(result.isValid)
    }

    func test_validator_destination_slugWithSpecialChars_isInvalid() {
        let result = DeepLinkValidator.validate(
            destination: .dashboard(tenantSlug: "acme/../evil")
        )
        XCTAssertFalse(result.isValid)
    }

    func test_validator_destination_shortMagicToken_isInvalid() {
        let result = DeepLinkValidator.validate(
            destination: .magicLink(tenantSlug: "acme", token: "short")
        )
        XCTAssertFalse(result.isValid)
    }

    func test_validator_destination_validMagicToken_isValid() {
        let result = DeepLinkValidator.validate(
            destination: .magicLink(tenantSlug: "acme", token: "abc12345678")
        )
        XCTAssertTrue(result.isValid)
    }

    func test_validator_destination_invalidPhone_isInvalid() {
        // Phone with angle bracket injection
        let result = DeepLinkValidator.validate(
            destination: .smsThread(tenantSlug: "acme", phone: "+1<script>alert(1)</script>")
        )
        XCTAssertFalse(result.isValid)
    }

    func test_validator_destination_validPhone_isValid() {
        let result = DeepLinkValidator.validate(
            destination: .smsThread(tenantSlug: "acme", phone: "+1 (415) 555-0100")
        )
        XCTAssertTrue(result.isValid)
    }

    func test_validator_destination_controlCharInID_isInvalid() {
        // ASCII BEL character (\u0007) injected into an ID
        let result = DeepLinkValidator.validate(
            destination: .ticket(tenantSlug: "acme", id: "T-1\u{0007}")
        )
        XCTAssertFalse(result.isValid)
    }

    func test_validator_destination_tooLongSearchQuery_isInvalid() {
        let longQuery = String(repeating: "a", count: 600)
        let result = DeepLinkValidator.validate(
            destination: .search(tenantSlug: "acme", query: longQuery)
        )
        XCTAssertFalse(result.isValid)
    }

    // =========================================================================
    // MARK: - 11. DeepLinkValidator.parseAndValidate — combined gate
    // =========================================================================

    func test_validator_parseAndValidate_validURL_returnsDestination() {
        let dest = DeepLinkValidator.parseAndValidate(
            url("bizarrecrm://acme/tickets/T-001")
        )
        XCTAssertEqual(dest, .ticket(tenantSlug: "acme", id: "T-001"))
    }

    func test_validator_parseAndValidate_unknownHost_returnsNil() {
        let dest = DeepLinkValidator.parseAndValidate(
            url("https://evil.com/acme/tickets/T-1")
        )
        XCTAssertNil(dest)
    }

    func test_validator_parseAndValidate_unknownResource_returnsNil() {
        let dest = DeepLinkValidator.parseAndValidate(
            url("bizarrecrm://acme/ponies/rainbow")
        )
        XCTAssertNil(dest)
    }

    // =========================================================================
    // MARK: - 12. Idempotency / purity
    // =========================================================================

    func test_parser_isIdempotent() {
        let u = url("bizarrecrm://acme/tickets/T-77")
        XCTAssertEqual(DeepLinkURLParser.parse(u), DeepLinkURLParser.parse(u))
    }

    func test_builder_isIdempotent() {
        let dest = DeepLinkDestination.invoice(tenantSlug: "acme", id: "INV-5")
        XCTAssertEqual(
            DeepLinkBuilder.build(dest, form: .customScheme),
            DeepLinkBuilder.build(dest, form: .customScheme)
        )
    }

    // =========================================================================
    // MARK: - 13. DeepLinkDestination.tenantSlug convenience accessor
    // =========================================================================

    func test_destination_tenantSlug_presentForResourceCases() {
        let cases: [DeepLinkDestination] = [
            .ticket(tenantSlug: "acme", id: "T-1"),
            .customer(tenantSlug: "acme", id: "C-1"),
            .invoice(tenantSlug: "acme", id: "INV-1"),
            .dashboard(tenantSlug: "acme"),
            .posRoot(tenantSlug: "acme"),
            .search(tenantSlug: "acme", query: nil),
        ]
        for dest in cases {
            XCTAssertEqual(dest.tenantSlug, "acme", "tenantSlug should be 'acme' for \(dest)")
        }
    }

    func test_destination_tenantSlug_nilForTenantlessMagicLink() {
        let dest = DeepLinkDestination.magicLink(tenantSlug: nil, token: "abc12345678")
        XCTAssertNil(dest.tenantSlug)
    }
}
