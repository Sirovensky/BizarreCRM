import XCTest
@testable import Auth

// MARK: - RecentServersStore tests

final class RecentServersStoreTests: XCTestCase {

    private var store: RecentServersStore!

    override func setUp() async throws {
        store = RecentServersStore()
        await store.clear()
    }

    // MARK: - Empty state

    func test_initial_isEmpty() async {
        let servers = await store.all
        XCTAssertTrue(servers.isEmpty)
    }

    // MARK: - Record

    func test_record_addsEntry() async {
        let url = URL(string: "https://myshop.bizarrecrm.com")!
        await store.record(url: url, name: "My Shop")
        let all = await store.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.displayName, "My Shop")
        XCTAssertEqual(all.first?.url, url)
    }

    func test_record_sameDomain_deduplicates() async {
        let url = URL(string: "https://myshop.bizarrecrm.com")!
        await store.record(url: url, name: "First")
        await store.record(url: url, name: "Updated")
        let all = await store.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.displayName, "Updated")
    }

    func test_record_newestFirst() async {
        let url1 = URL(string: "https://shop1.bizarrecrm.com")!
        let url2 = URL(string: "https://shop2.bizarrecrm.com")!
        await store.record(url: url1, name: "Shop 1")
        await store.record(url: url2, name: "Shop 2")
        let all = await store.all
        XCTAssertEqual(all.first?.displayName, "Shop 2")
    }

    func test_record_capsAtMaxCount() async {
        for i in 0..<7 {
            let url = URL(string: "https://shop\(i).bizarrecrm.com")!
            await store.record(url: url, name: "Shop \(i)")
        }
        let all = await store.all
        XCTAssertLessThanOrEqual(all.count, RecentServersStore.maxCount)
    }

    // MARK: - Clear

    func test_clear_removesAll() async {
        let url = URL(string: "https://myshop.bizarrecrm.com")!
        await store.record(url: url, name: "My Shop")
        await store.clear()
        let all = await store.all
        XCTAssertTrue(all.isEmpty)
    }
}
