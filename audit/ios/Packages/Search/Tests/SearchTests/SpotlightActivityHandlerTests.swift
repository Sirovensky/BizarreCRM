import XCTest
import CoreSpotlight
@testable import Search

// MARK: - SpotlightEntityReferenceTests

final class SpotlightEntityReferenceTests: XCTestCase {

    // MARK: - EntityKind raw values

    func test_entityKind_ticketRawValue() {
        XCTAssertEqual(SpotlightEntityReference.EntityKind.ticket.rawValue, "ticket")
    }

    func test_entityKind_customerRawValue() {
        XCTAssertEqual(SpotlightEntityReference.EntityKind.customer.rawValue, "customer")
    }

    func test_entityKind_inventoryRawValue() {
        XCTAssertEqual(SpotlightEntityReference.EntityKind.inventory.rawValue, "inventory")
    }

    func test_entityKind_allCases_hasThreeKinds() {
        XCTAssertEqual(SpotlightEntityReference.EntityKind.allCases.count, 3)
    }

    func test_entityKind_initFromRawValue_ticket() {
        XCTAssertEqual(SpotlightEntityReference.EntityKind(rawValue: "ticket"), .ticket)
    }

    func test_entityKind_initFromRawValue_customer() {
        XCTAssertEqual(SpotlightEntityReference.EntityKind(rawValue: "customer"), .customer)
    }

    func test_entityKind_initFromRawValue_inventory() {
        XCTAssertEqual(SpotlightEntityReference.EntityKind(rawValue: "inventory"), .inventory)
    }

    func test_entityKind_initFromRawValue_unknownReturnsNil() {
        XCTAssertNil(SpotlightEntityReference.EntityKind(rawValue: "invoice"))
    }

    // MARK: - Equatable

    func test_entityReference_equalityHoldsForSameValues() {
        let a = SpotlightEntityReference(kind: .ticket, entityId: 42, uniqueIdentifier: "bizarrecrm.ticket.42")
        let b = SpotlightEntityReference(kind: .ticket, entityId: 42, uniqueIdentifier: "bizarrecrm.ticket.42")
        XCTAssertEqual(a, b)
    }

    func test_entityReference_inequalityOnDifferentId() {
        let a = SpotlightEntityReference(kind: .ticket, entityId: 1, uniqueIdentifier: "bizarrecrm.ticket.1")
        let b = SpotlightEntityReference(kind: .ticket, entityId: 2, uniqueIdentifier: "bizarrecrm.ticket.2")
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - SpotlightActivityHandlerParseTests

final class SpotlightActivityHandlerParseTests: XCTestCase {

    // MARK: - Happy paths

    func test_parse_ticketIdentifier_returnsTicketReference() {
        let ref = SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.ticket.7")
        XCTAssertNotNil(ref)
        XCTAssertEqual(ref?.kind, .ticket)
        XCTAssertEqual(ref?.entityId, 7)
        XCTAssertEqual(ref?.uniqueIdentifier, "bizarrecrm.ticket.7")
    }

    func test_parse_customerIdentifier_returnsCustomerReference() {
        let ref = SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.customer.99")
        XCTAssertEqual(ref?.kind, .customer)
        XCTAssertEqual(ref?.entityId, 99)
    }

    func test_parse_inventoryIdentifier_returnsInventoryReference() {
        let ref = SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.inventory.1234")
        XCTAssertEqual(ref?.kind, .inventory)
        XCTAssertEqual(ref?.entityId, 1234)
    }

    func test_parse_largeId_parsedCorrectly() {
        let ref = SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.ticket.9007199254740992")
        XCTAssertNotNil(ref)
        XCTAssertEqual(ref?.entityId, 9_007_199_254_740_992)
    }

    // MARK: - Malformed identifiers

    func test_parse_wrongPrefix_returnsNil() {
        XCTAssertNil(SpotlightActivityHandler.parse(uniqueIdentifier: "otherapp.ticket.1"))
    }

    func test_parse_tooFewComponents_returnsNil() {
        XCTAssertNil(SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.ticket"))
    }

    func test_parse_tooManyComponents_returnsNil() {
        // "bizarrecrm.ticket.42.extra" splits into 4 parts — should fail
        XCTAssertNil(SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.ticket.42.extra"))
    }

    func test_parse_unknownDomain_returnsNil() {
        XCTAssertNil(SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.invoice.5"))
    }

    func test_parse_nonNumericId_returnsNil() {
        XCTAssertNil(SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.ticket.abc"))
    }

    func test_parse_emptyString_returnsNil() {
        XCTAssertNil(SpotlightActivityHandler.parse(uniqueIdentifier: ""))
    }

    func test_parse_emptyId_returnsNil() {
        XCTAssertNil(SpotlightActivityHandler.parse(uniqueIdentifier: "bizarrecrm.ticket."))
    }
}

// MARK: - SpotlightActivityHandlerActivityTests

final class SpotlightActivityHandlerActivityTests: XCTestCase {

    // MARK: - entityReference(from:)

    func test_entityReference_wrongActivityType_returnsNil() {
        let activity = NSUserActivity(activityType: "com.bizarrecrm.someOtherType")
        XCTAssertNil(SpotlightActivityHandler.entityReference(from: activity))
    }

    func test_entityReference_missingUserInfo_returnsNil() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        // userInfo is nil by default
        XCTAssertNil(SpotlightActivityHandler.entityReference(from: activity))
    }

    func test_entityReference_missingIdentifierKey_returnsNil() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = ["someOtherKey": "value"]
        XCTAssertNil(SpotlightActivityHandler.entityReference(from: activity))
    }

    func test_entityReference_validTicketActivity_returnsTicketRef() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "bizarrecrm.ticket.42"]
        let ref = SpotlightActivityHandler.entityReference(from: activity)
        XCTAssertEqual(ref?.kind, .ticket)
        XCTAssertEqual(ref?.entityId, 42)
    }

    func test_entityReference_validCustomerActivity_returnsCustomerRef() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "bizarrecrm.customer.17"]
        let ref = SpotlightActivityHandler.entityReference(from: activity)
        XCTAssertEqual(ref?.kind, .customer)
        XCTAssertEqual(ref?.entityId, 17)
    }

    func test_entityReference_validInventoryActivity_returnsInventoryRef() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "bizarrecrm.inventory.88"]
        let ref = SpotlightActivityHandler.entityReference(from: activity)
        XCTAssertEqual(ref?.kind, .inventory)
        XCTAssertEqual(ref?.entityId, 88)
    }

    func test_entityReference_malformedIdentifier_returnsNil() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "garbage"]
        XCTAssertNil(SpotlightActivityHandler.entityReference(from: activity))
    }
}

// MARK: - SpotlightDeepLinkResolverTests

final class SpotlightDeepLinkResolverTests: XCTestCase {

    // MARK: - destination(for:)

    func test_destination_ticketReference_returnsTicketDestination() {
        let ref = SpotlightEntityReference(kind: .ticket, entityId: 10, uniqueIdentifier: "bizarrecrm.ticket.10")
        XCTAssertEqual(SpotlightDeepLinkResolver.destination(for: ref), .ticket(id: 10))
    }

    func test_destination_customerReference_returnsCustomerDestination() {
        let ref = SpotlightEntityReference(kind: .customer, entityId: 20, uniqueIdentifier: "bizarrecrm.customer.20")
        XCTAssertEqual(SpotlightDeepLinkResolver.destination(for: ref), .customer(id: 20))
    }

    func test_destination_inventoryReference_returnsInventoryDestination() {
        let ref = SpotlightEntityReference(kind: .inventory, entityId: 30, uniqueIdentifier: "bizarrecrm.inventory.30")
        XCTAssertEqual(SpotlightDeepLinkResolver.destination(for: ref), .inventoryItem(id: 30))
    }

    func test_destination_preservesEntityId() {
        let id: Int64 = 9_876_543
        let ref = SpotlightEntityReference(kind: .ticket, entityId: id, uniqueIdentifier: "bizarrecrm.ticket.\(id)")
        if case .ticket(let resolvedId) = SpotlightDeepLinkResolver.destination(for: ref) {
            XCTAssertEqual(resolvedId, id)
        } else {
            XCTFail("Expected .ticket destination")
        }
    }

    // MARK: - destination(forIdentifier:) convenience overload

    func test_destinationForIdentifier_validTicket_returnsTicketDestination() {
        XCTAssertEqual(
            SpotlightDeepLinkResolver.destination(forIdentifier: "bizarrecrm.ticket.5"),
            .ticket(id: 5)
        )
    }

    func test_destinationForIdentifier_validCustomer_returnsCustomerDestination() {
        XCTAssertEqual(
            SpotlightDeepLinkResolver.destination(forIdentifier: "bizarrecrm.customer.200"),
            .customer(id: 200)
        )
    }

    func test_destinationForIdentifier_validInventory_returnsInventoryDestination() {
        XCTAssertEqual(
            SpotlightDeepLinkResolver.destination(forIdentifier: "bizarrecrm.inventory.3"),
            .inventoryItem(id: 3)
        )
    }

    func test_destinationForIdentifier_malformed_returnsNil() {
        XCTAssertNil(SpotlightDeepLinkResolver.destination(forIdentifier: "not.a.valid.id"))
    }

    func test_destinationForIdentifier_emptyString_returnsNil() {
        XCTAssertNil(SpotlightDeepLinkResolver.destination(forIdentifier: ""))
    }

    func test_destinationForIdentifier_unknownDomain_returnsNil() {
        XCTAssertNil(SpotlightDeepLinkResolver.destination(forIdentifier: "bizarrecrm.invoice.1"))
    }

    // MARK: - Equatable

    func test_destination_equatableTicketSameId() {
        XCTAssertEqual(
            SpotlightDeepLinkDestination.ticket(id: 1),
            SpotlightDeepLinkDestination.ticket(id: 1)
        )
    }

    func test_destination_equatableTicketDifferentId() {
        XCTAssertNotEqual(
            SpotlightDeepLinkDestination.ticket(id: 1),
            SpotlightDeepLinkDestination.ticket(id: 2)
        )
    }

    func test_destination_equatableDifferentKinds() {
        XCTAssertNotEqual(
            SpotlightDeepLinkDestination.ticket(id: 1),
            SpotlightDeepLinkDestination.customer(id: 1)
        )
    }
}
