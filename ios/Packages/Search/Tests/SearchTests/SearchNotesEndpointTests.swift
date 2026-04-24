import XCTest
@testable import Search
import Networking

// MARK: - SearchNotesResponse decoding tests

final class SearchNotesEndpointTests: XCTestCase {

    // MARK: - Decoding

    func test_searchNotesResponse_decodesEmptyNotes() throws {
        let json = """
        {
            "success": true,
            "data": {
                "notes": [],
                "pagination": { "page": 1, "per_page": 20, "total": 0, "total_pages": 0 }
            }
        }
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(APIResponse<SearchNotesResponse>.self, from: json)
        XCTAssertTrue(envelope.success)
        XCTAssertEqual(envelope.data?.notes.count, 0)
    }

    func test_searchNotesResponse_decodesNoteRow() throws {
        let json = """
        {
            "success": true,
            "data": {
                "notes": [
                    {
                        "id": 42,
                        "ticket_id": 7,
                        "type": "internal",
                        "content": "Battery replaced successfully.",
                        "created_at": "2024-01-15T10:30:00.000Z",
                        "order_id": "T-0007",
                        "device_name": "iPhone 14",
                        "author_first": "Jane",
                        "author_last": "Doe",
                        "customer_first": "Bob",
                        "customer_last": "Smith"
                    }
                ],
                "pagination": { "page": 1, "per_page": 20, "total": 1, "total_pages": 1 }
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(APIResponse<SearchNotesResponse>.self, from: json)
        let note = try XCTUnwrap(envelope.data?.notes.first)
        XCTAssertEqual(note.id, 42)
        XCTAssertEqual(note.ticketId, 7)
        XCTAssertEqual(note.type, "internal")
        XCTAssertEqual(note.content, "Battery replaced successfully.")
        XCTAssertEqual(note.orderId, "T-0007")
    }

    func test_searchNoteRow_authorName_fullName() throws {
        let json = """
        {
            "success": true,
            "data": {
                "notes": [
                    {
                        "id": 1,
                        "author_first": "Jane",
                        "author_last": "Doe",
                        "customer_first": null,
                        "customer_last": null
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(APIResponse<SearchNotesResponse>.self, from: json)
        let note = try XCTUnwrap(envelope.data?.notes.first)
        XCTAssertEqual(note.authorName, "Jane Doe")
    }

    func test_searchNoteRow_authorName_missingFirst() throws {
        let json = """
        {
            "success": true,
            "data": {
                "notes": [
                    {
                        "id": 2,
                        "author_first": null,
                        "author_last": "Doe",
                        "customer_first": null,
                        "customer_last": null
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(APIResponse<SearchNotesResponse>.self, from: json)
        let note = try XCTUnwrap(envelope.data?.notes.first)
        XCTAssertEqual(note.authorName, "Doe")
    }

    func test_searchNoteRow_customerName_fullName() throws {
        let json = """
        {
            "success": true,
            "data": {
                "notes": [
                    {
                        "id": 3,
                        "author_first": null,
                        "author_last": null,
                        "customer_first": "Alice",
                        "customer_last": "Smith"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(APIResponse<SearchNotesResponse>.self, from: json)
        let note = try XCTUnwrap(envelope.data?.notes.first)
        XCTAssertEqual(note.customerName, "Alice Smith")
    }

    func test_searchNotesResponse_pagination_decoded() throws {
        let json = """
        {
            "success": true,
            "data": {
                "notes": [],
                "pagination": { "page": 3, "per_page": 20, "total": 55, "total_pages": 3 }
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(APIResponse<SearchNotesResponse>.self, from: json)
        XCTAssertEqual(envelope.data?.pagination?.page, 3)
        XCTAssertEqual(envelope.data?.pagination?.total, 55)
        XCTAssertEqual(envelope.data?.pagination?.totalPages, 3)
        XCTAssertEqual(envelope.data?.pagination?.perPage, 20)
    }

    func test_searchNotesResponse_missingNotes_defaultsToEmpty() throws {
        // Server might omit "notes" on edge case — should not crash
        let json = """
        {
            "success": true,
            "data": {}
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(APIResponse<SearchNotesResponse>.self, from: json)
        XCTAssertEqual(envelope.data?.notes.count, 0)
    }

    // MARK: - SearchNoteRow.id conformance

    func test_searchNoteRow_identifiable_usesId() throws {
        let json = """
        {
            "success": true,
            "data": {
                "notes": [{ "id": 77 }]
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(APIResponse<SearchNotesResponse>.self, from: json)
        XCTAssertEqual(envelope.data?.notes.first?.id, 77)
    }
}
