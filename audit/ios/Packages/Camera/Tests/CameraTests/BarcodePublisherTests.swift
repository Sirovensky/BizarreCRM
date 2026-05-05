import XCTest
@testable import Camera

#if canImport(UIKit) && canImport(VisionKit)
import Combine
import UIKit
import VisionKit

/// Tests for the Combine publisher and AsyncStream surface on ``BarcodeCoordinator``.
@MainActor
final class BarcodePublisherTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() async throws {
        cancellables.removeAll()
    }

    // MARK: - barcodePublisher

    func test_barcodePublisher_emitsWhenPayloadScanned() {
        var received: [Barcode] = []
        let sut = BarcodeCoordinator(mode: .single) { _ in }

        sut.barcodePublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        sut.handleRawPayload("HELLO", symbology: "qr")
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].value, "HELLO")
        XCTAssertEqual(received[0].symbology, "qr")
    }

    func test_barcodePublisher_emitsCorrectSymbology() {
        var received: [Barcode] = []
        let sut = BarcodeCoordinator(mode: .continuous) { _ in }

        sut.barcodePublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        sut.handleRawPayload("123", symbology: "ean13")
        XCTAssertEqual(received.first?.symbology, "ean13")
    }

    func test_barcodePublisher_doesNotEmitBeforeAnyPayload() {
        var received: [Barcode] = []
        let sut = BarcodeCoordinator(mode: .single) { _ in }

        sut.barcodePublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        XCTAssertTrue(received.isEmpty)
    }

    func test_barcodePublisher_respectsDebounce() {
        var received: [Barcode] = []
        let sut = BarcodeCoordinator(mode: .continuous) { _ in }

        sut.barcodePublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        sut.handleRawPayload("A", symbology: "qr")
        sut.handleRawPayload("B", symbology: "qr") // within debounce window — should be ignored
        XCTAssertEqual(received.count, 1, "Publisher must not emit debounced duplicates")
    }

    func test_barcodePublisher_multipleSubscribers_allReceive() {
        var received1: [String] = []
        var received2: [String] = []
        let sut = BarcodeCoordinator(mode: .continuous) { _ in }

        sut.barcodePublisher
            .sink { received1.append($0.value) }
            .store(in: &cancellables)

        sut.barcodePublisher
            .sink { received2.append($0.value) }
            .store(in: &cancellables)

        sut.handleRawPayload("MULTI", symbology: "code128")
        XCTAssertEqual(received1, ["MULTI"])
        XCTAssertEqual(received2, ["MULTI"])
    }

    func test_barcodePublisher_afterCancelSubscription_doesNotReceive() {
        var received: [Barcode] = []
        let sut = BarcodeCoordinator(mode: .continuous) { _ in }

        var sub: AnyCancellable? = sut.barcodePublisher
            .sink { received.append($0) }
        sub?.cancel()
        sub = nil

        sut.handleRawPayload("GHOST")
        XCTAssertTrue(received.isEmpty, "Cancelled subscriber must not receive events")
    }

    // MARK: - barcodeStream (AsyncStream)

    func test_barcodeStream_yieldsScannedBarcode() async {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        var received: [Barcode] = []

        let task = Task {
            for await barcode in sut.barcodeStream() {
                received.append(barcode)
                break // exit after first item
            }
        }

        // Yield to let the async for-await loop start.
        await Task.yield()
        sut.handleRawPayload("STREAM-TEST", symbology: "qr")
        await task.value

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].value, "STREAM-TEST")
    }

    func test_barcodeStream_cancelledTask_doesNotLeak() async {
        let sut = BarcodeCoordinator(mode: .continuous) { _ in }

        let task = Task {
            for await _ in sut.barcodeStream() {
                // Intentionally never break — relies on task cancellation.
            }
        }

        await Task.yield()
        task.cancel()
        await task.value // Should complete without hanging.
        // Reaching here means the stream terminated cleanly on cancellation.
    }

    func test_barcodeStream_multipleConcurrentStreams() async {
        let sut = BarcodeCoordinator(mode: .continuous) { _ in }
        var received1: [String] = []
        var received2: [String] = []

        let t1 = Task {
            for await b in sut.barcodeStream() {
                received1.append(b.value)
                break
            }
        }
        let t2 = Task {
            for await b in sut.barcodeStream() {
                received2.append(b.value)
                break
            }
        }

        await Task.yield()
        sut.handleRawPayload("PARALLEL", symbology: "qr")
        await t1.value
        await t2.value

        XCTAssertEqual(received1, ["PARALLEL"])
        XCTAssertEqual(received2, ["PARALLEL"])
    }
}

#endif
