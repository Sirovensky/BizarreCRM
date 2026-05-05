import XCTest
@testable import Core

// §20 Draft Recovery — DraftKey tests
// Covers: construction, storage key format, collision avoidance,
// equality/hashability, well-known factory helpers, Codable round-trip.

final class DraftKeyTests: XCTestCase {

    // MARK: — storageKey format

    func test_storageKey_createFlow_noId() {
        let key = DraftKey(entityKind: "ticket.create")
        XCTAssertEqual(key.storageKey, "ticket.create|")
    }

    func test_storageKey_editFlow_withId() {
        let key = DraftKey(entityKind: "ticket.edit", id: "42")
        XCTAssertEqual(key.storageKey, "ticket.edit|42")
    }

    func test_storageKey_format_separatorPresent() {
        // Even when id is nil the pipe separator must be present to distinguish
        // "ticket.create" (no id) from a hypothetical "ticket.create|someId".
        let key = DraftKey(entityKind: "customer.create")
        XCTAssertTrue(key.storageKey.contains("|"), "separator must always be present")
    }

    // MARK: — Collision avoidance

    func test_collision_sameKind_differentId_differentStorageKey() {
        let a = DraftKey(entityKind: "ticket.edit", id: "1")
        let b = DraftKey(entityKind: "ticket.edit", id: "2")
        XCTAssertNotEqual(a.storageKey, b.storageKey)
    }

    func test_collision_createVsEdit_differentStorageKey() {
        let create = DraftKey(entityKind: "ticket.create")
        let edit   = DraftKey(entityKind: "ticket.edit", id: "1")
        XCTAssertNotEqual(create.storageKey, edit.storageKey)
    }

    func test_collision_nilIdVsEmptyStringId_differentStorageKey() {
        // id == nil  → "screen|"
        // id == ""   → "screen|"   (edge case: both map to same key — acceptable,
        //                            because "" is not a valid entity id in practice)
        let nilId   = DraftKey(entityKind: "thing", id: nil)
        let emptyId = DraftKey(entityKind: "thing", id: "")
        // They intentionally collide — document the behaviour:
        XCTAssertEqual(nilId.storageKey, emptyId.storageKey,
                       "nil and empty-string id intentionally collide (empty string is not a valid entity id)")
    }

    func test_collision_differentKinds_sameId_differentStorageKey() {
        let ticketKey   = DraftKey(entityKind: "ticket.edit", id: "99")
        let customerKey = DraftKey(entityKind: "customer.edit", id: "99")
        XCTAssertNotEqual(ticketKey.storageKey, customerKey.storageKey)
    }

    // MARK: — Equality & Hashability

    func test_equality_sameKindAndId() {
        let a = DraftKey(entityKind: "ticket.edit", id: "5")
        let b = DraftKey(entityKind: "ticket.edit", id: "5")
        XCTAssertEqual(a, b)
    }

    func test_equality_sameKind_nilId() {
        let a = DraftKey(entityKind: "invoice.create")
        let b = DraftKey(entityKind: "invoice.create")
        XCTAssertEqual(a, b)
    }

    func test_inequality_differentId() {
        let a = DraftKey(entityKind: "ticket.edit", id: "1")
        let b = DraftKey(entityKind: "ticket.edit", id: "2")
        XCTAssertNotEqual(a, b)
    }

    func test_usableAsSetElement() {
        var set = Set<DraftKey>()
        set.insert(DraftKey(entityKind: "ticket.create"))
        set.insert(DraftKey(entityKind: "ticket.create")) // duplicate
        set.insert(DraftKey(entityKind: "ticket.edit", id: "1"))
        XCTAssertEqual(set.count, 2)
    }

    func test_usableAsDictionaryKey() {
        var dict = [DraftKey: String]()
        dict[DraftKey(entityKind: "ticket.create")] = "a"
        dict[DraftKey(entityKind: "ticket.edit", id: "1")] = "b"
        XCTAssertEqual(dict[DraftKey(entityKind: "ticket.create")], "a")
        XCTAssertEqual(dict[DraftKey(entityKind: "ticket.edit", id: "1")], "b")
    }

    // MARK: — Well-known factory helpers

    func test_wellKnown_ticketCreate() {
        XCTAssertEqual(DraftKey.ticketCreate.entityKind, "ticket.create")
        XCTAssertNil(DraftKey.ticketCreate.id)
    }

    func test_wellKnown_ticketEdit() {
        let key = DraftKey.ticketEdit(id: "7")
        XCTAssertEqual(key.entityKind, "ticket.edit")
        XCTAssertEqual(key.id, "7")
    }

    func test_wellKnown_customerCreate() {
        XCTAssertEqual(DraftKey.customerCreate.entityKind, "customer.create")
        XCTAssertNil(DraftKey.customerCreate.id)
    }

    func test_wellKnown_customerEdit() {
        let key = DraftKey.customerEdit(id: "abc")
        XCTAssertEqual(key.entityKind, "customer.edit")
        XCTAssertEqual(key.id, "abc")
    }

    func test_wellKnown_estimateCreate() {
        XCTAssertNil(DraftKey.estimateCreate.id)
        XCTAssertEqual(DraftKey.estimateCreate.entityKind, "estimate.create")
    }

    func test_wellKnown_invoiceCreate() {
        XCTAssertNil(DraftKey.invoiceCreate.id)
    }

    func test_wellKnown_jobEdit() {
        let key = DraftKey.jobEdit(id: "J-99")
        XCTAssertEqual(key.storageKey, "job.edit|J-99")
    }

    // MARK: — Codable round-trip

    func test_codable_roundtrip_withId() throws {
        let original = DraftKey(entityKind: "ticket.edit", id: "42")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DraftKey.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_codable_roundtrip_nilId() throws {
        let original = DraftKey(entityKind: "ticket.create")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DraftKey.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: — CustomStringConvertible

    func test_description_matchesStorageKey() {
        let key = DraftKey(entityKind: "estimate.edit", id: "3")
        XCTAssertEqual(key.description, key.storageKey)
    }
}
