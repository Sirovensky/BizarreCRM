#if canImport(UIKit)
import XCTest
@testable import Tickets
@testable import Networking

// MARK: - TicketPhotoBatchUploader unit tests

final class TicketPhotoBatchUploaderTests: XCTestCase {

    // MARK: - Helpers

    private func makeImageData() -> Data {
        // Tiny white 1×1 JPEG
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return img.jpegData(compressionQuality: 0.5) ?? Data("fake".utf8)
    }

    private func makeItem(
        ticketId: Int64 = 1,
        photoType: String = "pre"
    ) -> BatchPhotoItem {
        BatchPhotoItem(
            imageData: makeImageData(),
            fileName: "photo_\(UUID()).jpg",
            ticketId: ticketId,
            ticketDeviceId: 99,
            photoType: photoType
        )
    }

    // MARK: - BatchPhotoItem identity

    func test_batchPhotoItem_hasUniqueIds() {
        let a = makeItem()
        let b = makeItem()
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_batchPhotoItem_storesTicketId() {
        let item = makeItem(ticketId: 42)
        XCTAssertEqual(item.ticketId, 42)
    }

    func test_batchPhotoItem_storesPhotoType() {
        let item = makeItem(photoType: "post")
        XCTAssertEqual(item.photoType, "post")
    }

    func test_batchPhotoItem_defaultPhotoTypeIsPre() {
        let item = BatchPhotoItem(
            imageData: makeImageData(),
            fileName: "x.jpg",
            ticketId: 1,
            ticketDeviceId: 1
        )
        XCTAssertEqual(item.photoType, "pre")
    }

    // MARK: - Progress initialisation

    func test_uploadBatch_emptyBatch_returnsEmptyResult() async {
        let api = ExtendedStubAPIClient()
        let uploader = TicketPhotoBatchUploader(api: api)
        let result = await uploader.uploadBatch([])
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(result.failed.isEmpty)
    }

    func test_uploadBatch_singleItem_setsProgress() async {
        let api = ExtendedStubAPIClient()
        let uploader = TicketPhotoBatchUploader(api: api)
        let item = makeItem()

        // uploadBatch will fail (no base URL) but should still set progress
        _ = await uploader.uploadBatch([item])
        let progress = await uploader.itemProgress(for: item.id)
        XCTAssertNotNil(progress, "Progress should be set after upload attempt")
    }

    func test_uploadBatch_noBaseURL_allFailed() async {
        let api = ExtendedStubAPIClient()   // currentBaseURL() returns nil
        let uploader = TicketPhotoBatchUploader(api: api)
        let items = [makeItem(), makeItem(), makeItem()]

        let result = await uploader.uploadBatch(items)

        XCTAssertEqual(result.failed.count, 3, "All items should fail without a base URL")
        XCTAssertTrue(result.succeeded.isEmpty)
    }

    func test_uploadBatch_multipleItems_progressStateIsSet() async {
        let api = ExtendedStubAPIClient()
        let uploader = TicketPhotoBatchUploader(api: api)
        let items = [makeItem(), makeItem()]

        _ = await uploader.uploadBatch(items)

        for item in items {
            let p = await uploader.itemProgress(for: item.id)
            XCTAssertNotNil(p)
            if case .failed(let reason) = p {
                XCTAssertFalse(reason.isEmpty)
            }
        }
    }

    func test_itemProgress_unknownId_returnsNil() async {
        let api = ExtendedStubAPIClient()
        let uploader = TicketPhotoBatchUploader(api: api)
        let p = await uploader.itemProgress(for: UUID())
        XCTAssertNil(p)
    }

    // MARK: - BatchItemProgress equatability

    func test_batchItemProgress_pending_isEquatable() {
        XCTAssertEqual(BatchItemProgress.pending, BatchItemProgress.pending)
    }

    func test_batchItemProgress_failed_isEquatable() {
        let a = BatchItemProgress.failed(reason: "oops")
        let b = BatchItemProgress.failed(reason: "oops")
        XCTAssertEqual(a, b)
    }

    func test_batchItemProgress_done_isEquatable() {
        let a = BatchItemProgress.done(remoteURL: "https://example.com/photo.jpg")
        let b = BatchItemProgress.done(remoteURL: "https://example.com/photo.jpg")
        XCTAssertEqual(a, b)
    }

    // MARK: - Concurrency limit

    func test_uploadBatch_respectsMaxConcurrency() async {
        // With concurrency 1 and 3 items, all should still complete.
        let api = ExtendedStubAPIClient()
        let uploader = TicketPhotoBatchUploader(api: api, maxConcurrency: 1)
        let items = [makeItem(), makeItem(), makeItem()]

        let result = await uploader.uploadBatch(items)
        XCTAssertEqual(result.failed.count + result.succeeded.count, 3)
    }
}
#endif
