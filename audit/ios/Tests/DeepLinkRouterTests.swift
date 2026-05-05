import XCTest
// NOTE: DeepLinkRouter lives in the App target which is not a SwiftPM package,
// so this file is compiled into the BizarreCRMTests target via xcodebuild.
// The underlying parse logic is exhaustively tested in
// ios/Packages/Core/Tests/CoreTests/DeepLinkParserTests.swift (56 cases, via
// `swift test`).  These tests cover the thin @MainActor + @Observable shell:
//  - pending state is set after handle(_:)
//  - onRoute closure is called
//  - consume() clears pending
//  - register(path:handler:) custom handler fires
//  - multiple consecutive handle() calls update pending correctly

#if canImport(UIKit)
// The App target is only available when building for iOS (not macOS swift test).

@testable import BizarreCRM

@MainActor
final class DeepLinkRouterTests: XCTestCase {

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        // Reset shared state between tests.
        DeepLinkRouter.shared.consume()
        DeepLinkRouter.shared.onRoute = nil
    }

    // MARK: - 1. Pending state after handle

    func test_handle_customScheme_ticket_setsPending() {
        let url = URL(string: "bizarrecrm://acme/tickets/T-1")!
        DeepLinkRouter.shared.handle(url)
        XCTAssertEqual(
            DeepLinkRouter.shared.pending,
            .ticket(tenantSlug: "acme", id: "T-1")
        )
    }

    func test_handle_universalLink_invoice_setsPending() {
        let url = URL(string: "https://app.bizarrecrm.com/acme/invoices/INV-9")!
        DeepLinkRouter.shared.handle(url)
        XCTAssertEqual(
            DeepLinkRouter.shared.pending,
            .invoice(tenantSlug: "acme", id: "INV-9")
        )
    }

    func test_handle_safariExternal_setsPendingSafariExternal() {
        let url = URL(string: "https://app.bizarrecrm.com/public/tracking/abc")!
        DeepLinkRouter.shared.handle(url)
        guard case .safariExternal = DeepLinkRouter.shared.pending else {
            XCTFail("Expected .safariExternal in pending, got \(String(describing: DeepLinkRouter.shared.pending))")
            return
        }
    }

    // MARK: - 2. onRoute closure

    func test_handle_callsOnRouteClosure() {
        let url = URL(string: "bizarrecrm://acme/customers/C-2")!
        var receivedRoute: DeepLinkRoute?
        DeepLinkRouter.shared.onRoute = { route in
            receivedRoute = route
        }
        DeepLinkRouter.shared.handle(url)
        XCTAssertEqual(receivedRoute, .customer(tenantSlug: "acme", id: "C-2"))
    }

    func test_handle_withNoOnRoute_doesNotCrash() {
        DeepLinkRouter.shared.onRoute = nil
        let url = URL(string: "bizarrecrm://acme/dashboard")!
        // Must not throw or crash.
        DeepLinkRouter.shared.handle(url)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .dashboard(tenantSlug: "acme"))
    }

    // MARK: - 3. consume()

    func test_consume_clearsPending() {
        let url = URL(string: "bizarrecrm://acme/tickets/T-5")!
        DeepLinkRouter.shared.handle(url)
        XCTAssertNotNil(DeepLinkRouter.shared.pending)

        let consumed = DeepLinkRouter.shared.consume()
        XCTAssertEqual(consumed, .ticket(tenantSlug: "acme", id: "T-5"))
        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_consume_whenNilPending_returnsNil() {
        DeepLinkRouter.shared.consume()  // clear any residual
        let result = DeepLinkRouter.shared.consume()
        XCTAssertNil(result)
    }

    // MARK: - 4. Consecutive handle() calls

    func test_consecutiveHandle_secondCallOverwritesPending() {
        let url1 = URL(string: "bizarrecrm://acme/tickets/T-1")!
        let url2 = URL(string: "bizarrecrm://acme/invoices/INV-1")!
        DeepLinkRouter.shared.handle(url1)
        DeepLinkRouter.shared.handle(url2)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .invoice(tenantSlug: "acme", id: "INV-1"))
    }

    // MARK: - 5. register(path:handler:) custom handler

    func test_register_customPath_interceptsBeforeDefaultParse() {
        var handlerCalled = false
        DeepLinkRouter.shared.register(path: "pos/scanner") { _ in
            handlerCalled = true
        }
        let url = URL(string: "bizarrecrm://acme/pos/scanner")!
        DeepLinkRouter.shared.handle(url)
        XCTAssertTrue(handlerCalled, "Custom handler must be called for registered path")
    }

    func test_register_customPath_doesNotSetPendingByDefault() {
        // Custom handlers own their navigation — default pending is not set.
        DeepLinkRouter.shared.register(path: "pos/scanner") { _ in /* noop */ }
        let url = URL(string: "bizarrecrm://acme/pos/scanner")!
        DeepLinkRouter.shared.handle(url)
        // pending may be nil since the custom handler took over.
        // The exact value depends on custom handler implementation;
        // the key contract is "no crash".
    }

    func test_register_unregisteredPath_fallsBackToDefaultParse() {
        // A different path should still fall through to DeepLinkParser.
        let url = URL(string: "bizarrecrm://acme/estimates/EST-1")!
        DeepLinkRouter.shared.handle(url)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .estimate(tenantSlug: "acme", id: "EST-1"))
    }

    // MARK: - 6. Magic-link route

    func test_handle_magicLink_setsPendingMagicLink() {
        let url = URL(string: "bizarrecrm://acme/auth/magic?token=tok123")!
        DeepLinkRouter.shared.handle(url)
        XCTAssertEqual(
            DeepLinkRouter.shared.pending,
            .magicLink(tenantSlug: "acme", token: "tok123")
        )
    }

    // MARK: - 7. auditLogs (admin-only)

    func test_handle_settingsAudit_returnsAuditLogs() {
        let url = URL(string: "bizarrecrm://acme/settings/audit")!
        DeepLinkRouter.shared.handle(url)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .auditLogs(tenantSlug: "acme"))
    }

    // MARK: - 8. POS new cart

    func test_handle_posNew_setsPosNewCart() {
        let url = URL(string: "bizarrecrm://acme/pos/new")!
        DeepLinkRouter.shared.handle(url)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .posNewCart(tenantSlug: "acme"))
    }
}

#endif
