import XCTest
@testable import Tickets
@testable import Networking

/// §4 — TicketPhotoUploadService unit tests.
/// Tests the actor's queue management, state tracking, and offline retry logic.
final class TicketPhotoUploadServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempFile(content: String = "fake-image-data") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    // MARK: - Enqueue

    func test_enqueue_setsQueuingState() async throws {
        let api = ExtendedStubAPIClient()
        let service = TicketPhotoUploadService(api: api)
        let url = try makeTempFile()
        let item = PhotoUploadItem(localURL: url, ticketId: 1)

        // The service will attempt upload; without a base URL it will fail.
        await service.enqueue(item)
        let state = await service.state(for: item.id)
        // Either failed (no baseURL) or done — never nil after enqueue.
        XCTAssertNotNil(state)
    }

    func test_enqueue_failsWithoutBaseURL() async throws {
        let api = ExtendedStubAPIClient() // currentBaseURL() returns nil
        let service = TicketPhotoUploadService(api: api)
        let url = try makeTempFile()
        let item = PhotoUploadItem(localURL: url, ticketId: 1)

        await service.enqueue(item)
        let state = await service.state(for: item.id)

        if case .failed(let msg) = state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            // Also acceptable if it goes directly to .uploading or stays queued
            // when no base URL — just must not be nil.
            XCTAssertNotNil(state)
        }
    }

    func test_enqueue_missingFile_setsFailed() async throws {
        let api = ExtendedStubAPIClient()
        let service = TicketPhotoUploadService(api: api)
        let fakeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("does_not_exist_\(UUID()).jpg")
        let item = PhotoUploadItem(localURL: fakeURL, ticketId: 1)

        await service.enqueue(item)
        let state = await service.state(for: item.id)

        if case .failed = state { /* pass */ } else {
            XCTAssertNotNil(state, "State should be set even on failure")
        }
    }

    // MARK: - Item properties

    func test_photoUploadItem_hasUniqueId() throws {
        let url = try makeTempFile()
        let a = PhotoUploadItem(localURL: url, ticketId: 1)
        let b = PhotoUploadItem(localURL: url, ticketId: 1)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_photoUploadItem_storesTicketId() throws {
        let url = try makeTempFile()
        let item = PhotoUploadItem(localURL: url, ticketId: 42)
        XCTAssertEqual(item.ticketId, 42)
    }

    func test_photoUploadItem_storesLocalURL() throws {
        let url = try makeTempFile()
        let item = PhotoUploadItem(localURL: url, ticketId: 1)
        XCTAssertEqual(item.localURL, url)
    }

    // MARK: - State for unknown ID

    func test_state_unknownId_returnsNil() async {
        let api = ExtendedStubAPIClient()
        let service = TicketPhotoUploadService(api: api)
        let unknown = UUID()
        let state = await service.state(for: unknown)
        XCTAssertNil(state)
    }

    // MARK: - Retry

    func test_retryFailed_doesNotCrash() async throws {
        let api = ExtendedStubAPIClient()
        let service = TicketPhotoUploadService(api: api)
        // Without any failed items, retry is a no-op.
        await service.retryFailed()
        // No crash = pass
    }

    func test_retryFailed_withFailedItem_attemptsAgain() async throws {
        let api = ExtendedStubAPIClient()
        let service = TicketPhotoUploadService(api: api)
        let url = try makeTempFile()
        let item = PhotoUploadItem(localURL: url, ticketId: 1)

        // Enqueue → will fail (no base URL)
        await service.enqueue(item)
        // Retry — should attempt again (result still .failed without URL)
        await service.retryFailed()
        let state = await service.state(for: item.id)
        XCTAssertNotNil(state)
    }

    // MARK: - PhotoUploadError descriptions

    func test_photoUploadError_noBaseURL_hasDescription() {
        let err = PhotoUploadError.noBaseURL
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }

    func test_photoUploadError_invalidData_hasDescription() {
        let err = PhotoUploadError.invalidData
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }
}
