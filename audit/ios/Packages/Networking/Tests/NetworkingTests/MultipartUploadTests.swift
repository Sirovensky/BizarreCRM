import XCTest
@testable import Networking

// MARK: - §1.1 MultipartUploadTests
//
// Validates the body shape produced by the `APIClient.upload(_:to:…)` helper.
// The helper uses a *background* `URLSession` internally — those can't be
// stubbed via `URLProtocol` — so this test exercises the body builder along
// the exact same code path the helper uses (same `MultipartFormData` API,
// fields-first / file-last ordering, stable boundary) and asserts:
//   • the chosen boundary appears as a delimiter
//   • each field has a `Content-Disposition: form-data; name="…"` line
//   • the file part has filename + mime + raw bytes
//   • the body ends with the closing boundary `--<boundary>--\r\n`

final class MultipartUploadTests: XCTestCase {

    // Helper: replicates the exact body-construction sequence inside
    // `APIClientImpl.upload(_:to:fileName:mimeType:fields:)`.
    private func buildUploadBody(
        boundary: String,
        fileName: String,
        mimeType: String,
        data: Data,
        fields: [(String, String)]
    ) -> (body: Data, contentType: String) {
        var form = MultipartFormData(boundary: boundary)
        for (k, v) in fields {
            form.appendField(name: k, value: v)
        }
        form.appendFile(
            name: "file",
            filename: fileName,
            mimeType: mimeType,
            data: data
        )
        return form.encode()
    }

    // MARK: - Boundary + Content-Type header

    func testContentTypeHeaderIncludesBoundary() {
        let (_, contentType) = buildUploadBody(
            boundary: "BOUNDARY-XYZ",
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data("hello".utf8),
            fields: [("ticketId", "42")]
        )
        XCTAssertEqual(contentType, "multipart/form-data; boundary=BOUNDARY-XYZ")
    }

    // MARK: - Body shape

    func testBodyHasExpectedBoundaryAndDispositionLines() {
        let boundary = "BOUNDARY-XYZ"
        let (body, _) = buildUploadBody(
            boundary: boundary,
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data("hello".utf8),
            fields: [
                ("ticketId", "42"),
                ("caption", "before")
            ]
        )
        let text = String(data: body, encoding: .utf8)!

        // Opening boundary appears at least once for each part (2 fields + 1 file = 3).
        let occurrences = text.components(separatedBy: "--\(boundary)").count - 1
        // 3 opening + 1 closing = 4 occurrences of `--BOUNDARY-XYZ`.
        XCTAssertEqual(occurrences, 4, "expected 4 boundary occurrences for 2 fields + 1 file")

        // Field headers: each must have a Content-Disposition line.
        XCTAssertTrue(
            text.contains("Content-Disposition: form-data; name=\"ticketId\"\r\n"),
            "ticketId Content-Disposition header missing"
        )
        XCTAssertTrue(
            text.contains("Content-Disposition: form-data; name=\"caption\"\r\n"),
            "caption Content-Disposition header missing"
        )

        // File part header: name + filename + Content-Type.
        XCTAssertTrue(
            text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n"),
            "file part Content-Disposition header missing or malformed"
        )
        XCTAssertTrue(
            text.contains("Content-Type: image/jpeg\r\n"),
            "file part Content-Type header missing"
        )

        // File content present.
        XCTAssertTrue(text.contains("hello"), "file bytes missing from body")
    }

    func testBodyEndsWithClosingBoundary() {
        let boundary = "BOUNDARY-XYZ"
        let (body, _) = buildUploadBody(
            boundary: boundary,
            fileName: "receipt.pdf",
            mimeType: "application/pdf",
            data: Data([0x25, 0x50, 0x44, 0x46]), // %PDF
            fields: [("expenseId", "7")]
        )
        let text = String(data: body, encoding: .isoLatin1)
            ?? String(decoding: body, as: UTF8.self)
        XCTAssertTrue(
            text.hasSuffix("--\(boundary)--\r\n"),
            "body must end with closing `--<boundary>--\\r\\n`"
        )
    }

    // MARK: - Ordering: fields first, file last

    func testFieldsAppearBeforeFilePart() {
        let boundary = "B"
        let (body, _) = buildUploadBody(
            boundary: boundary,
            fileName: "avatar.png",
            mimeType: "image/png",
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            fields: [("userId", "99")]
        )
        let text = String(data: body, encoding: .isoLatin1)
            ?? String(decoding: body, as: UTF8.self)

        let fieldRange = text.range(of: "name=\"userId\"")
        let fileRange = text.range(of: "name=\"file\"")
        XCTAssertNotNil(fieldRange, "userId field part not found")
        XCTAssertNotNil(fileRange, "file part not found")
        if let f = fieldRange, let g = fileRange {
            XCTAssertLessThan(f.lowerBound, g.lowerBound,
                              "scalar fields must appear before the binary file part")
        }
    }

    // MARK: - Configuration constants

    func testBackgroundSessionIdentifierMatchesContract() {
        XCTAssertEqual(
            APIClientImpl.backgroundUploadSessionIdentifier,
            "com.bizarrecrm.upload"
        )
    }

    func testBackgroundSharedContainerIdentifierMatchesAppGroup() {
        XCTAssertEqual(
            APIClientImpl.backgroundUploadSharedContainerIdentifier,
            "group.com.bizarrecrm"
        )
    }

    // MARK: - No baseURL → throws .noBaseURL

    func testUploadThrowsNoBaseURLWhenUnset() async {
        let api = APIClientImpl(initialBaseURL: nil)
        do {
            _ = try await api.upload(
                Data("x".utf8),
                to: "/photos",
                fileName: "x.jpg",
                mimeType: "image/jpeg",
                fields: [:]
            )
            XCTFail("expected APITransportError.noBaseURL")
        } catch APITransportError.noBaseURL {
            // expected
        } catch {
            XCTFail("expected .noBaseURL, got \(error)")
        }
    }
}
