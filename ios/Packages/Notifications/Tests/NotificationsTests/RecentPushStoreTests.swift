import XCTest
@testable import Notifications

// MARK: - §70 RecentPushStore tests

final class RecentPushStoreTests: XCTestCase {

    private var sut: RecentPushStore!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "com.test.recentpush.\(UUID().uuidString)")!
        sut = RecentPushStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        defaults = nil
        sut = nil
    }

    // MARK: - Append

    func test_append_singleRecord_storesIt() async {
        let record = RecentPushRecord(
            receivedAt: Date(),
            categoryID: "test",
            title: "Title",
            body: "Body"
        )
        await sut.append(record)
        let all = await sut.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].title, "Title")
    }

    func test_append_multipleRecords_newestFirst() async {
        for i in 1...5 {
            let r = RecentPushRecord(receivedAt: Date(), categoryID: "c", title: "T\(i)", body: "B")
            await sut.append(r)
        }
        let all = await sut.all()
        XCTAssertEqual(all.first?.title, "T5")
    }

    // MARK: - Cap

    func test_append_exceedsMax_evictsOldest() async {
        for i in 1...(RecentPushStore.maxCount + 10) {
            let r = RecentPushRecord(receivedAt: Date(), categoryID: "c", title: "T\(i)", body: "B")
            await sut.append(r)
        }
        let all = await sut.all()
        XCTAssertEqual(all.count, RecentPushStore.maxCount)
    }

    // MARK: - Clear

    func test_clearAll_removesAllRecords() async {
        let r = RecentPushRecord(receivedAt: Date(), categoryID: "c", title: "T", body: "B")
        await sut.append(r)
        await sut.clearAll()
        let all = await sut.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Convenience record()

    func test_record_withUserInfo_extractsEntityAndEventType() async {
        let userInfo: [AnyHashable: Any] = [
            "entity_id": "TKT-99",
            "event_type": "ticket.assigned"
        ]
        await sut.record(title: "Ticket", body: "Assigned", categoryID: "cat", userInfo: userInfo)
        let all = await sut.all()
        XCTAssertEqual(all.first?.entityID, "TKT-99")
        XCTAssertEqual(all.first?.eventType, "ticket.assigned")
    }
}
