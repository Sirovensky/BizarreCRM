import XCTest
@testable import Networking

// MARK: - MultipartFormDataTests
//
// Validates RFC 7578 encoding: boundary delimiters, part headers, field and
// file content appear in the correct order.

final class MultipartFormDataTests: XCTestCase {

    // MARK: - Boundary

    func testCustomBoundaryIsUsed() {
        let form = MultipartFormData(boundary: "test-boundary-123")
        XCTAssertEqual(form.boundary, "test-boundary-123")
    }

    func testDefaultBoundaryIsNonEmpty() {
        let form = MultipartFormData()
        XCTAssertFalse(form.boundary.isEmpty)
    }

    func testTwoInstancesHaveDifferentDefaultBoundaries() {
        let a = MultipartFormData()
        let b = MultipartFormData()
        XCTAssertNotEqual(a.boundary, b.boundary)
    }

    // MARK: - Content-Type header value

    func testEncodeReturnsCorrectContentTypeHeaderValue() {
        let form = MultipartFormData(boundary: "abc")
        let (_, contentType) = form.encode()
        XCTAssertEqual(contentType, "multipart/form-data; boundary=abc")
    }

    // MARK: - Empty form

    func testEmptyFormProducesOnlyTerminatingBoundary() {
        let form = MultipartFormData(boundary: "B")
        let (body, _) = form.encode()
        let text = String(data: body, encoding: .utf8)!
        XCTAssertEqual(text, "--B--\r\n")
    }

    // MARK: - Single field

    func testSingleFieldBodyContainsBoundaryAndValue() {
        var form = MultipartFormData(boundary: "B")
        form.appendField(name: "username", value: "alice")
        let (body, _) = form.encode()
        let text = String(data: body, encoding: .utf8)!

        XCTAssertTrue(text.contains("--B\r\n"), "opening boundary missing")
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"username\"\r\n"), "disposition header missing")
        XCTAssertTrue(text.contains("\r\nalice\r\n"), "field value missing")
        XCTAssertTrue(text.hasSuffix("--B--\r\n"), "closing boundary missing")
    }

    func testFieldDoesNotContainContentTypeHeader() {
        var form = MultipartFormData(boundary: "B")
        form.appendField(name: "n", value: "v")
        let (body, _) = form.encode()
        let text = String(data: body, encoding: .utf8)!
        // Plain text fields must NOT include a Content-Type line
        let lines = text.components(separatedBy: "\r\n")
        let contentTypeLines = lines.filter { $0.lowercased().hasPrefix("content-type") }
        XCTAssertTrue(contentTypeLines.isEmpty, "field should not carry a Content-Type header")
    }

    // MARK: - Single file

    func testSingleFileBodyContainsFilenameAndMimeType() {
        var form = MultipartFormData(boundary: "B")
        let data = Data("hello".utf8)
        form.appendFile(name: "upload", filename: "hello.txt", mimeType: "text/plain", data: data)
        let (body, _) = form.encode()
        let text = String(data: body, encoding: .utf8)!

        XCTAssertTrue(text.contains("filename=\"hello.txt\""), "filename missing")
        XCTAssertTrue(text.contains("Content-Type: text/plain\r\n"), "mime type missing")
        XCTAssertTrue(text.contains("hello"), "file content missing")
    }

    func testFileBinaryDataIsPreserved() {
        let originalData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes
        var form = MultipartFormData(boundary: "B")
        form.appendFile(name: "img", filename: "image.png", mimeType: "image/png", data: originalData)
        let (body, _) = form.encode()

        // Locate the PNG bytes in the raw body
        let bodyBytes = [UInt8](body)
        let pattern: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let found = bodyBytes.windows(ofCount: 4).contains { Array($0) == pattern }
        XCTAssertTrue(found, "binary file data not preserved in encoded body")
    }

    // MARK: - Field + file ordering

    func testFieldThenFileOrder() {
        var form = MultipartFormData(boundary: "B")
        form.appendField(name: "description", value: "test")
        form.appendFile(name: "file", filename: "f.bin", mimeType: "application/octet-stream", data: Data([0x01]))

        let (body, _) = form.encode()
        let text = String(data: body, encoding: .utf8)!

        let fieldRange = text.range(of: "name=\"description\"")!
        let fileRange = text.range(of: "name=\"file\"")!
        XCTAssertTrue(fieldRange.lowerBound < fileRange.lowerBound,
                      "field must appear before file part")
    }

    func testFileThenFieldOrder() {
        var form = MultipartFormData(boundary: "B")
        form.appendFile(name: "photo", filename: "p.jpg", mimeType: "image/jpeg", data: Data([0xFF]))
        form.appendField(name: "caption", value: "Nice")

        let (body, _) = form.encode()
        let text = String(data: body, encoding: .utf8)!

        let fileRange = text.range(of: "name=\"photo\"")!
        let fieldRange = text.range(of: "name=\"caption\"")!
        XCTAssertTrue(fileRange.lowerBound < fieldRange.lowerBound,
                      "file must appear before field when added first")
    }

    // MARK: - Multiple fields and files

    func testMultiplePartsProduceMultipleBoundaryOccurrences() {
        var form = MultipartFormData(boundary: "X")
        form.appendField(name: "a", value: "1")
        form.appendField(name: "b", value: "2")
        form.appendFile(name: "c", filename: "c.dat", mimeType: "application/octet-stream", data: Data([0x00]))

        let (body, _) = form.encode()
        let text = String(data: body, encoding: .utf8)!

        // 3 parts → 3 opening boundaries + 1 closing = 4 occurrences of "--X"
        let count = text.components(separatedBy: "--X").count - 1
        XCTAssertEqual(count, 4, "expected 4 boundary occurrences for 3 parts")
    }

    // MARK: - Immutable (value-copy) API

    func testAppendingFieldReturnsNewCopy() {
        let original = MultipartFormData(boundary: "B")
        let withField = original.appendingField(name: "key", value: "val")

        let (originalBody, _) = original.encode()
        let (withFieldBody, _) = withField.encode()

        // Original should still only have the terminating boundary.
        let originalText = String(data: originalBody, encoding: .utf8)!
        XCTAssertFalse(originalText.contains("key"), "original must not be mutated")
        XCTAssertTrue(String(data: withFieldBody, encoding: .utf8)!.contains("key"))
    }

    func testAppendingFileReturnsNewCopy() {
        let original = MultipartFormData(boundary: "B")
        let withFile = original.appendingFile(
            name: "doc",
            filename: "doc.pdf",
            mimeType: "application/pdf",
            data: Data([0x25, 0x50, 0x44, 0x46])
        )

        let (originalBody, _) = original.encode()
        let originalText = String(data: originalBody, encoding: .utf8)!
        XCTAssertFalse(originalText.contains("doc"), "original must not be mutated")
        XCTAssertTrue(String(data: withFile.encode().body, encoding: .utf8)!.contains("doc.pdf"))
    }

    // MARK: - Idempotency

    func testEncodeTwiceProducesSameResult() {
        var form = MultipartFormData(boundary: "stable")
        form.appendField(name: "x", value: "y")
        let (body1, ct1) = form.encode()
        let (body2, ct2) = form.encode()
        XCTAssertEqual(body1, body2, "encode() must be idempotent")
        XCTAssertEqual(ct1, ct2)
    }

    // MARK: - URLRequest integration

    func testApplyMultipartFormSetsContentTypeHeader() throws {
        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        var form = MultipartFormData(boundary: "FIXED")
        form.appendField(name: "hello", value: "world")
        request.applyMultipartForm(form)

        let ct = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(ct, "multipart/form-data; boundary=FIXED")
    }

    func testApplyMultipartFormSetsContentLengthHeader() throws {
        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        var form = MultipartFormData(boundary: "FIXED")
        form.appendField(name: "k", value: "v")
        let body = request.applyMultipartForm(form)

        let lengthHeader = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Length"))
        XCTAssertEqual(lengthHeader, String(body.count))
    }

    func testApplyMultipartFormSetsHttpBody() {
        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        var form = MultipartFormData(boundary: "FIXED")
        form.appendField(name: "n", value: "v")
        let returned = request.applyMultipartForm(form)

        XCTAssertEqual(request.httpBody, returned)
        XCTAssertNotNil(request.httpBody)
    }

    func testApplyMultipartFormWithAuthTokenSetsAuthorizationHeader() throws {
        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        let form = MultipartFormData(boundary: "B")
        request.applyMultipartForm(form, authToken: "secret-token")

        let auth = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(auth, "Bearer secret-token")
    }

    func testApplyingMultipartFormDoesNotMutateOriginal() {
        let original = URLRequest(url: URL(string: "https://example.com/upload")!)
        var form = MultipartFormData(boundary: "B")
        form.appendField(name: "x", value: "y")

        let (copy, _) = original.applyingMultipartForm(form)

        XCTAssertNil(original.httpBody, "original request must not be mutated")
        XCTAssertNotNil(copy.httpBody)
    }
}

// MARK: - Sequence windows helper (stdlib backport for < Swift 5.9)

private extension Array {
    func windows(ofCount size: Int) -> [[Element]] {
        guard size > 0, count >= size else { return [] }
        return (0 ... count - size).map { Array(self[$0 ..< $0 + size]) }
    }
}
