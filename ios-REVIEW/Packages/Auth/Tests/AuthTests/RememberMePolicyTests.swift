import XCTest
@testable import Auth

final class RememberMePolicyTests: XCTestCase {

    private var sut: RememberMePolicy!
    private let tenantId = "tenant-abc"

    override func setUp() {
        super.setUp()
        sut = RememberMePolicy()
        sut.forget(tenantId: tenantId) // clean slate
    }

    override func tearDown() {
        sut.forget(tenantId: tenantId)
        super.tearDown()
    }

    func test_save_andRetrieve() {
        sut.save(email: "alice@shop.com", tenantId: tenantId)
        XCTAssertEqual(sut.email(for: tenantId), "alice@shop.com")
    }

    func test_save_trimsWhitespace() {
        sut.save(email: "  bob@shop.com  ", tenantId: tenantId)
        XCTAssertEqual(sut.email(for: tenantId), "bob@shop.com")
    }

    func test_save_emptyEmail_isIgnored() {
        sut.save(email: "initial@shop.com", tenantId: tenantId)
        sut.save(email: "", tenantId: tenantId)
        // Empty save should not overwrite existing email
        XCTAssertEqual(sut.email(for: tenantId), "initial@shop.com")
    }

    func test_forget_clearsEmail() {
        sut.save(email: "carol@shop.com", tenantId: tenantId)
        sut.forget(tenantId: tenantId)
        XCTAssertNil(sut.email(for: tenantId))
    }

    func test_forgetAll_clearsAll() {
        let tid2 = "tenant-xyz"
        sut.save(email: "dave@a.com", tenantId: tenantId)
        sut.save(email: "eve@b.com", tenantId: tid2)
        sut.forgetAll()
        XCTAssertNil(sut.email(for: tenantId))
        XCTAssertNil(sut.email(for: tid2))
    }

    func test_perTenantScope_doesNotBleed() {
        let tid2 = "tenant-other"
        sut.save(email: "frank@a.com", tenantId: tenantId)
        sut.save(email: "grace@b.com", tenantId: tid2)
        XCTAssertEqual(sut.email(for: tenantId), "frank@a.com")
        XCTAssertEqual(sut.email(for: tid2), "grace@b.com")
    }

    func test_missingEmail_returnsNil() {
        XCTAssertNil(sut.email(for: "nonexistent-tenant"))
    }
}
