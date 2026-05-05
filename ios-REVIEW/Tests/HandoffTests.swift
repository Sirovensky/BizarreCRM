import XCTest
// NOTE: HandoffPublisher, HandoffReceiver, and HandoffEligibleModifier live in
// the App target, compiled via xcodebuild into BizarreCRMTests.
// Run with: xcodebuild test -scheme BizarreCRM -destination 'platform=iOS Simulator'

#if canImport(UIKit)

@testable import BizarreCRM

// MARK: - HandoffPublisherTests

@MainActor
final class HandoffPublisherTests: XCTestCase {

    // MARK: - Activity construction

    func test_publish_setsActivityType() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.ticketView,
            title: "Ticket #T-001",
            deepLinkURL: URL(string: "bizarrecrm://acme/tickets/1")!
        )
        defer { activity.invalidate() }
        XCTAssertEqual(activity.activityType, HandoffActivityType.ticketView)
    }

    func test_publish_setsTitle() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.ticketView,
            title: "Ticket #T-042",
            deepLinkURL: URL(string: "bizarrecrm://acme/tickets/42")!
        )
        defer { activity.invalidate() }
        XCTAssertEqual(activity.title, "Ticket #T-042")
    }

    func test_publish_isEligibleForHandoff() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.customerView,
            title: "Alice Smith",
            deepLinkURL: URL(string: "bizarrecrm://acme/customers/5")!
        )
        defer { activity.invalidate() }
        XCTAssertTrue(activity.isEligibleForHandoff)
    }

    func test_publish_isEligibleForSearch() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.customerView,
            title: "Alice Smith",
            deepLinkURL: URL(string: "bizarrecrm://acme/customers/5")!
        )
        defer { activity.invalidate() }
        XCTAssertTrue(activity.isEligibleForSearch)
    }

    func test_publish_isEligibleForPrediction() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.dashboard,
            title: "Dashboard",
            deepLinkURL: URL(string: "bizarrecrm://acme/dashboard")!
        )
        defer { activity.invalidate() }
        XCTAssertTrue(activity.isEligibleForPrediction)
    }

    func test_publish_storesDeepLinkURLInUserInfo() {
        let url = URL(string: "bizarrecrm://acme/tickets/99")!
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.ticketView,
            title: "Ticket #T-099",
            deepLinkURL: url
        )
        defer { activity.invalidate() }
        let stored = activity.userInfo?["deepLinkURL"] as? String
        XCTAssertEqual(stored, url.absoluteString)
    }

    func test_publish_storesEntityIdInUserInfo() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.ticketView,
            title: "Ticket",
            deepLinkURL: URL(string: "bizarrecrm://acme/tickets/7")!,
            entityId: "7"
        )
        defer { activity.invalidate() }
        let storedId = activity.userInfo?["entityId"] as? String
        XCTAssertEqual(storedId, "7")
    }

    func test_publish_noEntityId_entityIdKeyAbsent() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.ticketView,
            title: "Ticket",
            deepLinkURL: URL(string: "bizarrecrm://acme/tickets/3")!
        )
        defer { activity.invalidate() }
        XCTAssertNil(activity.userInfo?["entityId"])
    }

    func test_publish_setsWebpageURL_forCustomScheme() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.ticketView,
            title: "Ticket",
            deepLinkURL: URL(string: "bizarrecrm://acme/tickets/12")!
        )
        defer { activity.invalidate() }
        XCTAssertNotNil(activity.webpageURL)
        XCTAssertEqual(activity.webpageURL?.host, "app.bizarrecrm.com")
    }

    func test_publish_webpageURL_preservesPath() {
        let activity = HandoffPublisher.shared.publish(
            activityType: HandoffActivityType.ticketView,
            title: "Ticket",
            deepLinkURL: URL(string: "bizarrecrm://acme/tickets/12")!
        )
        defer { activity.invalidate() }
        // Path should contain the slug + resource + id
        let path = activity.webpageURL?.path ?? ""
        XCTAssertTrue(path.contains("acme"))
        XCTAssertTrue(path.contains("tickets"))
        XCTAssertTrue(path.contains("12"))
    }

    func test_publish_allActivityTypes_areEligibleForHandoff() {
        let types = [
            HandoffActivityType.ticketView,
            HandoffActivityType.customerView,
            HandoffActivityType.invoiceView,
            HandoffActivityType.dashboard,
        ]
        for type in types {
            let url = URL(string: "bizarrecrm://acme/dashboard")!
            let activity = HandoffPublisher.shared.publish(
                activityType: type, title: "Test", deepLinkURL: url
            )
            defer { activity.invalidate() }
            XCTAssertTrue(activity.isEligibleForHandoff, "Expected handoff eligible for \(type)")
        }
    }
}

// MARK: - HandoffReceiverTests

@MainActor
final class HandoffReceiverTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        DeepLinkRouter.shared.consume()
        DeepLinkRouter.shared.onRoute = nil
    }

    // MARK: - handle via userInfo deepLinkURL

    func test_handle_withDeepLinkURL_routesCorrectly() {
        let activity = NSUserActivity(activityType: HandoffActivityType.ticketView)
        activity.userInfo = ["deepLinkURL": "bizarrecrm://acme/tickets/55"]

        let handled = HandoffReceiver.shared.handle(activity)

        XCTAssertTrue(handled)
        if case .ticket(let slug, let id) = DeepLinkRouter.shared.pending {
            XCTAssertEqual(slug, "acme")
            XCTAssertEqual(id, "55")
        } else {
            XCTFail("Expected .ticket route, got \(String(describing: DeepLinkRouter.shared.pending))")
        }
    }

    func test_handle_withCustomerDeepLink_routesCustomer() {
        let activity = NSUserActivity(activityType: HandoffActivityType.customerView)
        activity.userInfo = ["deepLinkURL": "bizarrecrm://acme/customers/88"]

        HandoffReceiver.shared.handle(activity)

        if case .customer(let slug, let id) = DeepLinkRouter.shared.pending {
            XCTAssertEqual(slug, "acme")
            XCTAssertEqual(id, "88")
        } else {
            XCTFail("Expected .customer route")
        }
    }

    func test_handle_fallsBackToWebpageURL() {
        let activity = NSUserActivity(activityType: HandoffActivityType.ticketView)
        // No userInfo — only webpageURL (continuation from web/Mac)
        activity.webpageURL = URL(string: "https://app.bizarrecrm.com/acme/tickets/77")

        let handled = HandoffReceiver.shared.handle(activity)
        XCTAssertTrue(handled)

        if case .ticket(let slug, let id) = DeepLinkRouter.shared.pending {
            XCTAssertEqual(slug, "acme")
            XCTAssertEqual(id, "77")
        } else {
            XCTFail("Expected .ticket from webpage URL fallback")
        }
    }

    func test_handle_noURLs_returnsFalse() {
        let activity = NSUserActivity(activityType: HandoffActivityType.ticketView)
        // No userInfo, no webpageURL
        let handled = HandoffReceiver.shared.handle(activity)
        XCTAssertFalse(handled)
        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_handle_malformedDeepLinkURL_returnsFalse() {
        let activity = NSUserActivity(activityType: HandoffActivityType.ticketView)
        activity.userInfo = ["deepLinkURL": "not a url ://##"]

        // URL(string:) will return nil for this — should fall through to webpageURL
        // (which is also nil) → returns false
        let handled = HandoffReceiver.shared.handle(activity)
        XCTAssertFalse(handled)
    }

    func test_handle_invoiceDeepLink_routesInvoice() {
        let activity = NSUserActivity(activityType: HandoffActivityType.invoiceView)
        activity.userInfo = ["deepLinkURL": "bizarrecrm://acme/invoices/INV-001"]

        HandoffReceiver.shared.handle(activity)

        if case .invoice(let slug, let id) = DeepLinkRouter.shared.pending {
            XCTAssertEqual(slug, "acme")
            XCTAssertEqual(id, "INV-001")
        } else {
            XCTFail("Expected .invoice route")
        }
    }

    func test_handle_dashboardActivity_routesDashboard() {
        let activity = NSUserActivity(activityType: HandoffActivityType.dashboard)
        activity.userInfo = ["deepLinkURL": "bizarrecrm://acme/dashboard"]

        HandoffReceiver.shared.handle(activity)

        if case .dashboard(let slug) = DeepLinkRouter.shared.pending {
            XCTAssertEqual(slug, "acme")
        } else {
            XCTFail("Expected .dashboard route")
        }
    }
}

// MARK: - HandoffActivityTypeTests

final class HandoffActivityTypeTests: XCTestCase {

    func test_ticketViewActivityType_value() {
        XCTAssertEqual(HandoffActivityType.ticketView, "com.bizarrecrm.ticket.view")
    }

    func test_customerViewActivityType_value() {
        XCTAssertEqual(HandoffActivityType.customerView, "com.bizarrecrm.customer.view")
    }

    func test_invoiceViewActivityType_value() {
        XCTAssertEqual(HandoffActivityType.invoiceView, "com.bizarrecrm.invoice.view")
    }

    func test_dashboardActivityType_value() {
        XCTAssertEqual(HandoffActivityType.dashboard, "com.bizarrecrm.dashboard")
    }
}

#endif // canImport(UIKit)
