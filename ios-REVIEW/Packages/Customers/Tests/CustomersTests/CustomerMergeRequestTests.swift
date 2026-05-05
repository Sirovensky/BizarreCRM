import XCTest
import Networking

// §5.5 — Tests verifying CustomerMergeRequest JSON encoding matches server contract.
//
// Server (customers.routes.ts) destructures: const { keep_id, merge_id } = req.body
// iOS must send exactly those snake_case keys.

final class CustomerMergeRequestTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    func test_encoding_usesKeepIdAndMergeIdKeys() throws {
        let req = CustomerMergeRequest(keepId: 7, mergeId: 42)
        let data = try encoder.encode(req)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"keep_id\""),
                      "Expected key 'keep_id' in: \(json)")
        XCTAssertTrue(json.contains("\"merge_id\""),
                      "Expected key 'merge_id' in: \(json)")
    }

    func test_encoding_valuesMatchInputIds() throws {
        let req = CustomerMergeRequest(keepId: 123, mergeId: 456)
        let data = try encoder.encode(req)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let keepId = try XCTUnwrap(dict["keep_id"] as? Int)
        let mergeId = try XCTUnwrap(dict["merge_id"] as? Int)
        XCTAssertEqual(keepId, 123)
        XCTAssertEqual(mergeId, 456)
    }

    func test_encoding_doesNotContainFieldPreferences() throws {
        // The server does NOT accept field_preferences — ensure we never send it.
        let req = CustomerMergeRequest(keepId: 1, mergeId: 2)
        let data = try encoder.encode(req)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("field_preferences"),
                       "field_preferences must not appear in encoded body: \(json)")
        XCTAssertFalse(json.contains("primary_id"),
                       "primary_id must not appear in encoded body: \(json)")
        XCTAssertFalse(json.contains("secondary_id"),
                       "secondary_id must not appear in encoded body: \(json)")
    }

    func test_encoding_noExtraKeys() throws {
        // Exactly two keys: keep_id and merge_id.
        let req = CustomerMergeRequest(keepId: 5, mergeId: 6)
        let data = try encoder.encode(req)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(dict.keys.count, 2,
                       "Expected exactly 2 keys, got: \(dict.keys.sorted())")
        XCTAssertNotNil(dict["keep_id"])
        XCTAssertNotNil(dict["merge_id"])
    }

    func test_decoding_roundtrip() throws {
        // Verify the struct round-trips correctly.
        let original = CustomerMergeRequest(keepId: 99, mergeId: 77)
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(CustomerMergeRequest.self, from: data)

        XCTAssertEqual(decoded.keepId, 99)
        XCTAssertEqual(decoded.mergeId, 77)
    }
}
