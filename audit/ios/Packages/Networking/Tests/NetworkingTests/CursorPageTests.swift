import XCTest
@testable import Networking

final class CursorPageTests: XCTestCase {

    func testDecodesFromServerPayload() throws {
        let json = """
        {
          "data": [{"id": 1}, {"id": 2}],
          "next_cursor": "opaque-abc",
          "stream_end_at": null
        }
        """.data(using: .utf8)!

        struct Item: Decodable, Sendable, Equatable { let id: Int }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let page = try decoder.decode(CursorPage<Item>.self, from: json)

        XCTAssertEqual(page.data, [Item(id: 1), Item(id: 2)])
        XCTAssertEqual(page.nextCursor, "opaque-abc")
        XCTAssertNil(page.streamEndAt)
    }

    func testDecodesExhaustedStream() throws {
        let json = """
        {
          "data": [],
          "stream_end_at": "2026-04-20T12:00:00Z"
        }
        """.data(using: .utf8)!

        struct Item: Decodable, Sendable { let id: Int }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let page = try decoder.decode(CursorPage<Item>.self, from: json)

        XCTAssertTrue(page.data.isEmpty)
        XCTAssertNil(page.nextCursor)
        XCTAssertNotNil(page.streamEndAt)
    }

    func testDecodesMissingOptionalFields() throws {
        let json = """
        {"data": [{"id": 42}]}
        """.data(using: .utf8)!

        struct Item: Decodable, Sendable { let id: Int }

        let page = try JSONDecoder().decode(CursorPage<Item>.self, from: json)

        XCTAssertEqual(page.data.count, 1)
        XCTAssertNil(page.nextCursor)
        XCTAssertNil(page.streamEndAt)
    }
}
