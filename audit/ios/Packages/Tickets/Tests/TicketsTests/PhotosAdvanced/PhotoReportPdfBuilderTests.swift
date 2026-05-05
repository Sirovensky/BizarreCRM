#if canImport(UIKit)
import XCTest
@testable import Tickets

// MARK: - PhotoReportPdfBuilder unit tests

final class PhotoReportPdfBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeImage(color: UIColor = .systemBlue) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 150))
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
        }
    }

    private func defaultMetadata(title: String = "Test Report") -> PhotoReportMetadata {
        PhotoReportMetadata(
            title: title,
            ticketId: "12345",
            technicianName: "Alice",
            date: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Error cases

    func test_build_emptyPages_throwsNoPages() {
        let meta = defaultMetadata()
        XCTAssertThrowsError(try PhotoReportPdfBuilder.build(pages: [], metadata: meta)) { error in
            guard let reportError = error as? PhotoReportError else {
                XCTFail("Expected PhotoReportError, got \(error)")
                return
            }
            XCTAssertEqual(reportError, .noPages)
        }
    }

    // MARK: - Happy path

    func test_build_singlePage_producesNonEmptyData() throws {
        let page = PhotoReportPage(image: makeImage(), caption: "Front panel", tag: "pre")
        let data = try PhotoReportPdfBuilder.build(pages: [page], metadata: defaultMetadata())
        XCTAssertFalse(data.isEmpty, "PDF output should not be empty")
    }

    func test_build_multiplePagesEven_producesData() throws {
        let pages = (0..<4).map { i in
            PhotoReportPage(image: makeImage(color: .systemOrange), caption: "Shot \(i)", tag: i % 2 == 0 ? "pre" : "post")
        }
        let data = try PhotoReportPdfBuilder.build(pages: pages, metadata: defaultMetadata())
        XCTAssertFalse(data.isEmpty)
    }

    func test_build_oddNumberOfPages_producesData() throws {
        let pages = [
            PhotoReportPage(image: makeImage(), caption: "A"),
            PhotoReportPage(image: makeImage(), caption: "B"),
            PhotoReportPage(image: makeImage(), caption: "C")
        ]
        let data = try PhotoReportPdfBuilder.build(pages: pages, metadata: defaultMetadata())
        XCTAssertFalse(data.isEmpty)
    }

    func test_build_outputStartsWithPDFSignature() throws {
        let page = PhotoReportPage(image: makeImage())
        let data = try PhotoReportPdfBuilder.build(pages: [page], metadata: defaultMetadata())
        // PDF magic bytes: %PDF
        let magic = data.prefix(4)
        XCTAssertEqual(magic[0], 0x25) // %
        XCTAssertEqual(magic[1], 0x50) // P
        XCTAssertEqual(magic[2], 0x44) // D
        XCTAssertEqual(magic[3], 0x46) // F
    }

    func test_build_pageWithNilCaptionAndTag_doesNotCrash() throws {
        let page = PhotoReportPage(image: makeImage(), caption: nil, tag: nil)
        XCTAssertNoThrow(try PhotoReportPdfBuilder.build(pages: [page], metadata: defaultMetadata()))
    }

    func test_build_singlePageWithPostTag_producesData() throws {
        let page = PhotoReportPage(image: makeImage(color: .systemGreen), caption: "After repair", tag: "post")
        let data = try PhotoReportPdfBuilder.build(pages: [page], metadata: defaultMetadata(title: "Repair Report"))
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - Metadata

    func test_photoReportMetadata_defaultDateIsNow() {
        let before = Date()
        let meta = PhotoReportMetadata(title: "T", ticketId: "1")
        let after = Date()
        XCTAssertGreaterThanOrEqual(meta.date, before)
        XCTAssertLessThanOrEqual(meta.date, after)
    }

    func test_photoReportMetadata_storesTechnicianName() {
        let meta = PhotoReportMetadata(title: "T", ticketId: "1", technicianName: "Bob")
        XCTAssertEqual(meta.technicianName, "Bob")
    }

    // MARK: - Error descriptions

    func test_photoReportError_descriptions_areNonEmpty() {
        XCTAssertFalse(PhotoReportError.noPages.errorDescription?.isEmpty ?? true)
        XCTAssertFalse(PhotoReportError.renderFailed.errorDescription?.isEmpty ?? true)
    }
}
#endif
