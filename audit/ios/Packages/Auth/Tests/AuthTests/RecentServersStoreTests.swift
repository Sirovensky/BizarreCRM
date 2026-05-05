import XCTest
@testable import Auth

// MARK: - RecentServersStoreTests
// §79.1 — Verifies recent-servers persistence, ordering, and max-count trimming.

final class RecentServersStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RecentServersStore.clear()
    }

    func test_empty_onFirstLaunch() {
        XCTAssertTrue(RecentServersStore.all().isEmpty)
    }

    func test_record_storesServer() {
        let url = URL(string: "https://acme.bizarrecrm.com")!
        RecentServersStore.record(url: url, displayName: "Acme")
        let all = RecentServersStore.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.url, url)
        XCTAssertEqual(all.first?.displayName, "Acme")
    }

    func test_record_deduplicates() {
        let url = URL(string: "https://acme.bizarrecrm.com")!
        RecentServersStore.record(url: url, displayName: "Acme")
        RecentServersStore.record(url: url, displayName: "Acme v2")
        XCTAssertEqual(RecentServersStore.all().count, 1)
    }

    func test_record_mostRecentFirst() {
        let url1 = URL(string: "https://acme.bizarrecrm.com")!
        let url2 = URL(string: "https://beta.bizarrecrm.com")!
        RecentServersStore.record(url: url1, displayName: nil)
        RecentServersStore.record(url: url2, displayName: nil)
        XCTAssertEqual(RecentServersStore.all().first?.url, url2)
    }

    func test_record_trimsToFive() {
        for i in 0..<7 {
            let url = URL(string: "https://shop\(i).bizarrecrm.com")!
            RecentServersStore.record(url: url, displayName: nil)
        }
        XCTAssertEqual(RecentServersStore.all().count, 5)
    }

    func test_chipLabel_stripsCloudDomain() {
        let server = RecentServer(url: URL(string: "https://acme.bizarrecrm.com")!, displayName: nil)
        XCTAssertEqual(server.chipLabel, "acme")
    }

    func test_chipLabel_usesDisplayNameWhenAvailable() {
        let server = RecentServer(url: URL(string: "https://acme.bizarrecrm.com")!, displayName: "Acme Shop")
        XCTAssertEqual(server.chipLabel, "Acme Shop")
    }
}
