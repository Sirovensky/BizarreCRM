import XCTest
@testable import Camera

#if canImport(UIKit)
import UIKit

/// Tests for ``DocumentScanViewModel``.
///
/// Coverage goals (≥80%):
/// - addPages, deletePage, movePages, reorderPages (page management)
/// - generatePDF returns nil on empty / non-nil with pages
/// - attach: success path, failure path, empty-pages guard
/// - reset clears state
/// - UploadState transitions
@MainActor
final class DocumentScanViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Make a tiny 1×1 UIImage so tests are fast.
    private func makeImage(color: UIColor = .red) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func makeVM(
        uploader: @escaping @Sendable (Data) async throws -> String = { _ in "https://example.com/doc.pdf" }
    ) -> DocumentScanViewModel {
        DocumentScanViewModel(uploader: uploader)
    }

    // MARK: - Initial state

    func test_initial_pages_isEmpty() {
        let vm = makeVM()
        XCTAssertTrue(vm.pages.isEmpty)
    }

    func test_initial_uploadState_isIdle() {
        let vm = makeVM()
        XCTAssertEqual(vm.uploadState, .idle)
    }

    // MARK: - addPages

    func test_addPages_appendsToEmptyList() {
        let vm = makeVM()
        let images = [makeImage(), makeImage()]
        vm.addPages(images)
        XCTAssertEqual(vm.pages.count, 2)
    }

    func test_addPages_appendsToExistingList() {
        let vm = makeVM()
        vm.addPages([makeImage()])
        vm.addPages([makeImage(), makeImage()])
        XCTAssertEqual(vm.pages.count, 3)
    }

    func test_addPages_preservesOrder() {
        let vm = makeVM()
        let red = makeImage(color: .red)
        let blue = makeImage(color: .blue)
        vm.addPages([red, blue])
        // Verify same instances in same order.
        XCTAssertIdentical(vm.pages[0], red)
        XCTAssertIdentical(vm.pages[1], blue)
    }

    func test_addPages_empty_doesNotChange() {
        let vm = makeVM()
        vm.addPages([makeImage()])
        vm.addPages([])
        XCTAssertEqual(vm.pages.count, 1)
    }

    // MARK: - deletePage

    func test_deletePage_removesCorrectIndex() {
        let vm = makeVM()
        let a = makeImage(color: .red)
        let b = makeImage(color: .blue)
        let c = makeImage(color: .green)
        vm.addPages([a, b, c])
        vm.deletePage(at: 1) // remove b
        XCTAssertEqual(vm.pages.count, 2)
        XCTAssertIdentical(vm.pages[0], a)
        XCTAssertIdentical(vm.pages[1], c)
    }

    func test_deletePage_outOfBounds_isNoOp() {
        let vm = makeVM()
        vm.addPages([makeImage()])
        vm.deletePage(at: 5) // no-op
        XCTAssertEqual(vm.pages.count, 1)
    }

    func test_deletePage_emptyList_isNoOp() {
        let vm = makeVM()
        vm.deletePage(at: 0) // no-op on empty
        XCTAssertTrue(vm.pages.isEmpty)
    }

    func test_deletePage_lastItem_leavesEmptyList() {
        let vm = makeVM()
        vm.addPages([makeImage()])
        vm.deletePage(at: 0)
        XCTAssertTrue(vm.pages.isEmpty)
    }

    // MARK: - movePages

    func test_movePages_reordersCorrectly() {
        let vm = makeVM()
        let a = makeImage(color: .red)
        let b = makeImage(color: .blue)
        let c = makeImage(color: .green)
        vm.addPages([a, b, c])
        // Move index 0 (a) to after index 2 → [b, c, a]
        vm.movePages(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertIdentical(vm.pages[0], b)
        XCTAssertIdentical(vm.pages[1], c)
        XCTAssertIdentical(vm.pages[2], a)
    }

    func test_movePages_fromEnd_toStart() {
        let vm = makeVM()
        let a = makeImage(color: .red)
        let b = makeImage(color: .blue)
        vm.addPages([a, b])
        // Move index 1 (b) to offset 0 → [b, a]
        vm.movePages(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertIdentical(vm.pages[0], b)
        XCTAssertIdentical(vm.pages[1], a)
    }

    // MARK: - reorderPages

    func test_reorderPages_replacesEntireList() {
        let vm = makeVM()
        let a = makeImage(color: .red)
        let b = makeImage(color: .blue)
        vm.addPages([a, b])
        vm.reorderPages([b, a])
        XCTAssertIdentical(vm.pages[0], b)
        XCTAssertIdentical(vm.pages[1], a)
    }

    func test_reorderPages_toEmpty_clearsPages() {
        let vm = makeVM()
        vm.addPages([makeImage()])
        vm.reorderPages([])
        XCTAssertTrue(vm.pages.isEmpty)
    }

    // MARK: - generatePDF

    func test_generatePDF_emptyPages_returnsNil() {
        let vm = makeVM()
        XCTAssertNil(vm.generatePDF())
    }

    func test_generatePDF_withPages_returnsNonEmptyData() {
        let vm = makeVM()
        vm.addPages([makeImage()])
        let data = vm.generatePDF()
        XCTAssertNotNil(data)
        XCTAssertFalse(data!.isEmpty)
    }

    func test_generatePDF_withMultiplePages_returnsData() {
        let vm = makeVM()
        vm.addPages([makeImage(), makeImage(), makeImage()])
        let data = vm.generatePDF()
        XCTAssertNotNil(data)
        XCTAssertFalse(data!.isEmpty)
    }

    func test_generatePDF_doesNotMutatePages() {
        let vm = makeVM()
        vm.addPages([makeImage()])
        let countBefore = vm.pages.count
        _ = vm.generatePDF()
        XCTAssertEqual(vm.pages.count, countBefore)
    }

    // MARK: - assemblePDF (free function)

    func test_assemblePDF_emptyImages_returnsData() {
        // Empty input is valid — PDFKit returns an empty document data blob.
        let data = assemblePDF(from: [])
        // Should be a valid PDF header or empty; not crash.
        XCTAssertNotNil(data)
    }

    func test_assemblePDF_singleImage_producesPDFHeader() {
        let data = assemblePDF(from: [makeImage()])
        // %PDF- header is the first 5 bytes of any PDF.
        let header = String(data: data.prefix(5), encoding: .ascii) ?? ""
        XCTAssertEqual(header, "%PDF-", "assemblePDF output must begin with %PDF-")
    }

    // MARK: - attach — success

    func test_attach_setsUploadingThenSuccess() async {
        var states: [DocumentScanViewModel.UploadState] = []
        let vm = DocumentScanViewModel(uploader: { _ in
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return "https://cdn.example.com/doc.pdf"
        })
        vm.addPages([makeImage()])
        // Observe state transitions via polling.
        let task = Task { await vm.attach() }
        // Yield briefly so the VM hits .uploading.
        await Task.yield()
        states.append(vm.uploadState)
        await task.value
        states.append(vm.uploadState)

        XCTAssertTrue(states.contains(.uploading), "Should pass through .uploading")
        if case .success(let url) = vm.uploadState {
            XCTAssertEqual(url, "https://cdn.example.com/doc.pdf")
        } else {
            XCTFail("Expected .success, got \(vm.uploadState)")
        }
    }

    func test_attach_success_setsSuccessUrl() async {
        let expectedURL = "https://example.com/attachments/doc-123.pdf"
        let vm = DocumentScanViewModel(uploader: { _ in expectedURL })
        vm.addPages([makeImage()])
        await vm.attach()
        if case .success(let url) = vm.uploadState {
            XCTAssertEqual(url, expectedURL)
        } else {
            XCTFail("Expected .success, got \(vm.uploadState)")
        }
    }

    // MARK: - attach — failure

    func test_attach_failure_setsFailureMessage() async {
        struct UploadError: Error, LocalizedError {
            var errorDescription: String? { "Network unavailable" }
        }
        let vm = DocumentScanViewModel(uploader: { _ in throw UploadError() })
        vm.addPages([makeImage()])
        await vm.attach()
        if case .failure(let msg) = vm.uploadState {
            XCTAssertTrue(msg.contains("Network unavailable"))
        } else {
            XCTFail("Expected .failure, got \(vm.uploadState)")
        }
    }

    func test_attach_emptyPages_setsFailureWithoutCallingUploader() async {
        var uploaderCalled = false
        let vm = DocumentScanViewModel(uploader: { _ in
            uploaderCalled = true
            return "https://example.com/doc.pdf"
        })
        // No pages added.
        await vm.attach()
        XCTAssertFalse(uploaderCalled, "Uploader must not be called when there are no pages")
        if case .failure = vm.uploadState {
            // expected
        } else {
            XCTFail("Expected .failure when no pages, got \(vm.uploadState)")
        }
    }

    // MARK: - reset

    func test_reset_clearsPagesAndState() async {
        let vm = DocumentScanViewModel(uploader: { _ in "https://example.com/doc.pdf" })
        vm.addPages([makeImage(), makeImage()])
        await vm.attach()
        vm.reset()
        XCTAssertTrue(vm.pages.isEmpty)
        XCTAssertEqual(vm.uploadState, .idle)
    }
}
#endif
