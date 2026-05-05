import XCTest
@testable import Communications

final class MmsSizeEstimatorTests: XCTestCase {

    // MARK: - estimateTotalBytes

    func test_empty_isZero() {
        let total = MmsSizeEstimator.estimateTotalBytes(attachments: [])
        XCTAssertEqual(total, 0)
    }

    func test_singleAttachment_matchesSize() {
        let a = MmsAttachment(id: UUID(), kind: .image, url: URL(string: "file:///a.jpg")!, sizeBytes: 512_000, mimeType: "image/jpeg")
        XCTAssertEqual(MmsSizeEstimator.estimateTotalBytes(attachments: [a]), 512_000)
    }

    func test_multipleAttachments_sumsAll() {
        let a1 = MmsAttachment(id: UUID(), kind: .image, url: URL(string: "file:///a.jpg")!, sizeBytes: 200_000, mimeType: "image/jpeg")
        let a2 = MmsAttachment(id: UUID(), kind: .audio, url: URL(string: "file:///b.mp3")!, sizeBytes: 300_000, mimeType: "audio/mpeg")
        XCTAssertEqual(MmsSizeEstimator.estimateTotalBytes(attachments: [a1, a2]), 500_000)
    }

    // MARK: - exceedsCarrierLimit

    func test_belowLimit_notExceeded() {
        let a = MmsAttachment(id: UUID(), kind: .image, url: URL(string: "file:///a.jpg")!, sizeBytes: 500_000, mimeType: "image/jpeg")
        XCTAssertFalse(MmsSizeEstimator.exceedsCarrierLimit(attachments: [a]))
    }

    func test_atLimit_notExceeded() {
        let a = MmsAttachment(id: UUID(), kind: .file, url: URL(string: "file:///f.pdf")!, sizeBytes: MmsSizeEstimator.carrierLimitBytes, mimeType: "application/pdf")
        XCTAssertFalse(MmsSizeEstimator.exceedsCarrierLimit(attachments: [a]))
    }

    func test_aboveLimit_exceeded() {
        let a = MmsAttachment(id: UUID(), kind: .video, url: URL(string: "file:///v.mp4")!, sizeBytes: MmsSizeEstimator.carrierLimitBytes + 1, mimeType: "video/mp4")
        XCTAssertTrue(MmsSizeEstimator.exceedsCarrierLimit(attachments: [a]))
    }

    // MARK: - warningMessage

    func test_noWarning_whenUnderLimit() {
        let a = MmsAttachment(id: UUID(), kind: .image, url: URL(string: "file:///a.jpg")!, sizeBytes: 100_000, mimeType: "image/jpeg")
        XCTAssertNil(MmsSizeEstimator.warningMessage(attachments: [a]))
    }

    func test_warningPresent_whenOverLimit() {
        let a = MmsAttachment(id: UUID(), kind: .video, url: URL(string: "file:///v.mp4")!, sizeBytes: MmsSizeEstimator.carrierLimitBytes + 1_000, mimeType: "video/mp4")
        let msg = MmsSizeEstimator.warningMessage(attachments: [a])
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("MB"), "Warning should include size info")
    }

    // MARK: - formattedSize

    func test_formattedSize_kilobytes() {
        let s = MmsSizeEstimator.formattedSize(bytes: 512_000)
        XCTAssertTrue(s.contains("KB") || s.contains("MB"))
    }

    func test_formattedSize_megabytes() {
        let s = MmsSizeEstimator.formattedSize(bytes: 2_000_000)
        XCTAssertTrue(s.contains("MB"))
    }
}
