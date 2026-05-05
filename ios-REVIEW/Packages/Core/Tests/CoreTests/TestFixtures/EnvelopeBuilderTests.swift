import XCTest
@testable import Core

// §31 Test Fixtures Helpers — EnvelopeBuilder Tests
// Covers: success with encodable payload, success with empty body,
// success with raw dict, success with raw array,
// failure envelope, string convenience wrappers, error descriptions.

final class EnvelopeBuilderTests: XCTestCase {

    // MARK: — Helpers

    private func decode(_ data: Data) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            XCTFail("Top-level JSON is not a dictionary")
            return [:]
        }
        return dict
    }

    // MARK: — success(data:)

    func test_success_encodable_topLevelSuccessIsTrue() throws {
        let data = try EnvelopeBuilder.success(data: SimpleCodable(id: 7, label: "hello"))
        let dict = try decode(data)
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    func test_success_encodable_messageIsNull() throws {
        let data = try EnvelopeBuilder.success(data: SimpleCodable(id: 7, label: "hello"))
        let dict = try decode(data)
        XCTAssertTrue(dict["message"] is NSNull, "message should be NSNull for success envelope")
    }

    func test_success_encodable_dataContainsPayloadFields() throws {
        let payload = SimpleCodable(id: 42, label: "widget")
        let data = try EnvelopeBuilder.success(data: payload)
        let dict = try decode(data)
        let inner = try XCTUnwrap(dict["data"] as? [String: Any])
        XCTAssertEqual(inner["id"] as? Int, 42)
        XCTAssertEqual(inner["label"] as? String, "widget")
    }

    func test_success_encodable_allThreeTopLevelKeysPresent() throws {
        let data = try EnvelopeBuilder.success(data: SimpleCodable(id: 1, label: "x"))
        let dict = try decode(data)
        XCTAssertNotNil(dict["success"])
        XCTAssertNotNil(dict["data"])
        XCTAssertTrue(dict.keys.contains("message"))
    }

    // MARK: — successEmpty

    func test_successEmpty_topLevelSuccessIsTrue() throws {
        let data = EnvelopeBuilder.successEmpty()
        let dict = try decode(data)
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    func test_successEmpty_dataIsNull() throws {
        let data = EnvelopeBuilder.successEmpty()
        let dict = try decode(data)
        XCTAssertTrue(dict["data"] is NSNull)
    }

    // MARK: — successRaw

    func test_successRaw_embedsDictionaryUnderDataKey() throws {
        let payload: [String: Any] = ["key": "value", "count": 3]
        let data = EnvelopeBuilder.successRaw(data: payload)
        let dict = try decode(data)
        let inner = try XCTUnwrap(dict["data"] as? [String: Any])
        XCTAssertEqual(inner["key"] as? String, "value")
        XCTAssertEqual(inner["count"] as? Int, 3)
    }

    func test_successRaw_successIsTrue() throws {
        let data = EnvelopeBuilder.successRaw(data: [:])
        let dict = try decode(data)
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    // MARK: — successRawArray

    func test_successRawArray_embedsArrayUnderDataKey() throws {
        let payload: [[String: Any]] = [["id": 1], ["id": 2]]
        let data = EnvelopeBuilder.successRawArray(data: payload)
        let dict = try decode(data)
        let arr = try XCTUnwrap(dict["data"] as? [[String: Any]])
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr[0]["id"] as? Int, 1)
        XCTAssertEqual(arr[1]["id"] as? Int, 2)
    }

    // MARK: — failure

    func test_failure_successIsFalse() throws {
        let data = EnvelopeBuilder.failure(message: "Not found")
        let dict = try decode(data)
        XCTAssertEqual(dict["success"] as? Bool, false)
    }

    func test_failure_messageMatchesInput() throws {
        let data = EnvelopeBuilder.failure(message: "Unauthorized")
        let dict = try decode(data)
        XCTAssertEqual(dict["message"] as? String, "Unauthorized")
    }

    func test_failure_dataIsNull() throws {
        let data = EnvelopeBuilder.failure(message: "error")
        let dict = try decode(data)
        XCTAssertTrue(dict["data"] is NSNull)
    }

    // MARK: — String wrappers

    func test_successString_isValidJSON() throws {
        let str = try EnvelopeBuilder.successString(data: SimpleCodable(id: 5, label: "hi"))
        XCTAssertFalse(str.isEmpty)
        // Round-trip: string → Data → dict
        let backData = try XCTUnwrap(str.data(using: .utf8))
        let dict = try decode(backData)
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    func test_failureString_isValidJSON() {
        let str = EnvelopeBuilder.failureString(message: "boom")
        XCTAssertFalse(str.isEmpty)
        XCTAssertTrue(str.contains("false"))
        XCTAssertTrue(str.contains("boom"))
    }

    // MARK: — Error: encodingFailed description

    func test_encodingFailedError_descriptionMentionsUnderlying() {
        let underlying = NSError(domain: "TestDomain", code: 99, userInfo: [NSLocalizedDescriptionKey: "bad encode"])
        let err = EnvelopeBuilder.BuilderError.encodingFailed(underlying: underlying)
        XCTAssertTrue(err.description.lowercased().contains("encode") || err.description.contains("EnvelopeBuilder"))
    }
}

// MARK: — Local helpers

private struct SimpleCodable: Codable {
    let id: Int
    let label: String
}
