import XCTest
@testable import Auth

// MARK: - MultiUserRoster tests

final class MultiUserRosterTests: XCTestCase {

    // MARK: - Helpers

    private func makeUser(
        id: Int,
        username: String = "user",
        displayName: String = "Test User",
        email: String = "test@example.com",
        role: String = "staff"
    ) -> SwitchedUser {
        SwitchedUser(
            id: id,
            username: username,
            email: email,
            firstName: displayName,
            lastName: "",
            role: role,
            avatarUrl: nil,
            permissions: nil
        )
    }

    // MARK: - Initial state

    func test_initial_allIsEmpty_whenNoStoredData() async {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let entries = await roster.all
        XCTAssertTrue(entries.isEmpty)
    }

    func test_initial_allRestoresFromStorage() async {
        let salt = PINHasher.generateSalt()
        let hash = PINHasher.hash(pin: "1234", salt: salt)
        let existing = RosterEntry(
            id: 1, username: "alice", displayName: "Alice",
            email: "alice@test.com", role: "admin",
            avatarUrl: nil, pinSalt: salt, pinHash: hash
        )
        let storage = InMemoryRosterStorage(initial: [existing])
        let roster = MultiUserRoster(storage: storage)
        let entries = await roster.all
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, 1)
    }

    // MARK: - upsert

    func test_upsert_addsNewEntry() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let user = makeUser(id: 42, username: "bob", displayName: "Bob")
        try await roster.upsert(user: user, pin: "1234")
        let entries = await roster.all
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, 42)
    }

    func test_upsert_replacesExistingEntry() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let user = makeUser(id: 7)
        try await roster.upsert(user: user, pin: "1111")
        try await roster.upsert(user: user, pin: "2222")
        let entries = await roster.all
        XCTAssertEqual(entries.count, 1, "Should not duplicate entries for the same userId")
    }

    func test_upsert_persists_newPinHash() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let user = makeUser(id: 5)
        try await roster.upsert(user: user, pin: "1234")
        // Verify the new hash is queryable via match
        let found = await roster.match(pin: "1234")
        XCTAssertNotNil(found)
    }

    func test_upsert_multipleUsers_allPresent() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        try await roster.upsert(user: makeUser(id: 1, displayName: "Alice"), pin: "1111")
        try await roster.upsert(user: makeUser(id: 2, displayName: "Bob"), pin: "2222")
        let entries = await roster.all
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: - remove

    func test_remove_deletesExistingEntry() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        try await roster.upsert(user: makeUser(id: 10), pin: "0000")
        try await roster.remove(userId: 10)
        let entries = await roster.all
        XCTAssertTrue(entries.isEmpty)
    }

    func test_remove_isNoopForNonexistentId() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        try await roster.upsert(user: makeUser(id: 1), pin: "0000")
        try await roster.remove(userId: 999)
        let entries = await roster.all
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: - match

    func test_match_returnsEntryForCorrectPin() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let user = makeUser(id: 3, username: "carol")
        try await roster.upsert(user: user, pin: "4321")
        let result = await roster.match(pin: "4321")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.username, "carol")
    }

    func test_match_returnsNilForWrongPin() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        try await roster.upsert(user: makeUser(id: 3), pin: "4321")
        let result = await roster.match(pin: "0000")
        XCTAssertNil(result)
    }

    func test_match_returnsNilForEmptyRoster() async {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let result = await roster.match(pin: "1234")
        XCTAssertNil(result)
    }

    // MARK: - clear

    func test_clear_emptiesRoster() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        try await roster.upsert(user: makeUser(id: 1), pin: "1234")
        try await roster.upsert(user: makeUser(id: 2), pin: "5678")
        try await roster.clear()
        let entries = await roster.all
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - all (sorting)

    func test_all_returnsSortedByDisplayName() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        try await roster.upsert(user: makeUser(id: 3, displayName: "Zelda"), pin: "1111")
        try await roster.upsert(user: makeUser(id: 1, displayName: "Alice"), pin: "2222")
        try await roster.upsert(user: makeUser(id: 2, displayName: "Bob"), pin: "3333")
        let names = await roster.all.map(\.displayName)
        XCTAssertEqual(names, ["Alice", "Bob", "Zelda"])
    }
}
