import XCTest
@testable import Networking

final class APIResponseTests: XCTestCase {
    func test_decode_successEnvelope() throws {
        struct Payload: Decodable, Sendable, Equatable { let id: Int; let name: String }
        let json = #"{"success":true,"data":{"id":42,"name":"Sarah"},"error":null}"#.data(using: .utf8)!
        let env = try JSONDecoder.bizarre.decode(APIResponse<Payload>.self, from: json)
        XCTAssertTrue(env.success)
        XCTAssertEqual(env.data, Payload(id: 42, name: "Sarah"))
    }

    func test_decode_errorEnvelope() throws {
        struct Payload: Decodable, Sendable {}
        let json = #"{"success":false,"data":null,"error":{"code":"NOT_FOUND","message":"Ticket 42 not found"}}"#.data(using: .utf8)!
        let env = try JSONDecoder.bizarre.decode(APIResponse<Payload>.self, from: json)
        XCTAssertFalse(env.success)
        XCTAssertNil(env.data)
        XCTAssertEqual(env.error?.code, "NOT_FOUND")
    }
}
