import XCTest
import Combine
@testable import Networking

// MARK: - UploadProgressTrackerTests
//
// Verifies the Combine publisher emits correct progress fractions and
// completes on finish. Also covers the URLSessionTaskDelegate forwarding.

final class UploadProgressTrackerTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Initial state

    func testInitialProgressIsZero() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .sink { received.append($0) }
            .store(in: &cancellables)
        XCTAssertEqual(received, [0.0])
    }

    // MARK: - Update

    func testUpdateEmitsCorrectFraction() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst() // skip initial 0
            .sink { received.append($0) }
            .store(in: &cancellables)

        tracker.update(bytesSent: 500, totalBytes: 1000)
        XCTAssertEqual(received.last, 0.5, accuracy: 0.001)
    }

    func testUpdateClampsToOne() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst()
            .sink { received.append($0) }
            .store(in: &cancellables)

        // More bytes sent than total (edge case)
        tracker.update(bytesSent: 1500, totalBytes: 1000)
        XCTAssertEqual(received.last, 1.0)
    }

    func testUpdateIgnoresNegativeTotalBytes() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst()
            .sink { received.append($0) }
            .store(in: &cancellables)

        // totalBytes = -1 means unknown — tracker must ignore it
        tracker.update(bytesSent: 500, totalBytes: -1)
        XCTAssertTrue(received.isEmpty, "no emission expected when totalBytes is unknown")
    }

    func testUpdateIgnoresZeroTotalBytes() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst()
            .sink { received.append($0) }
            .store(in: &cancellables)

        tracker.update(bytesSent: 0, totalBytes: 0)
        XCTAssertTrue(received.isEmpty, "no emission expected when totalBytes is zero")
    }

    // MARK: - Sequence of updates

    func testProgressMonotonicallyIncreases() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst()
            .sink { received.append($0) }
            .store(in: &cancellables)

        tracker.update(bytesSent: 100, totalBytes: 1000)
        tracker.update(bytesSent: 400, totalBytes: 1000)
        tracker.update(bytesSent: 700, totalBytes: 1000)
        tracker.update(bytesSent: 1000, totalBytes: 1000)

        XCTAssertEqual(received.count, 4)
        for i in 1 ..< received.count {
            XCTAssertGreaterThanOrEqual(received[i], received[i - 1])
        }
        XCTAssertEqual(received.last!, 1.0, accuracy: 0.001)
    }

    // MARK: - Complete

    func testCompleteEmitsOne() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst()
            .sink { received.append($0) }
            .store(in: &cancellables)

        tracker.complete()
        XCTAssertEqual(received.last, 1.0)
    }

    // MARK: - URLSessionTaskDelegate forwarding

    func testDelegateBridgesProgressToPublisher() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst()
            .sink { received.append($0) }
            .store(in: &cancellables)

        // Simulate URLSession delegate callback
        tracker.urlSession(
            URLSession.shared,
            task: URLSession.shared.dataTask(with: URL(string: "https://example.com")!),
            didSendBodyData: 0,
            totalBytesSent: 250,
            totalBytesExpectedToSend: 1000
        )

        XCTAssertEqual(received.last, 0.25, accuracy: 0.001)
    }

    func testDelegateCompletionWithNoErrorCallsComplete() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst()
            .sink { received.append($0) }
            .store(in: &cancellables)

        tracker.urlSession(
            URLSession.shared,
            task: URLSession.shared.dataTask(with: URL(string: "https://example.com")!),
            didCompleteWithError: nil
        )

        XCTAssertEqual(received.last, 1.0)
    }

    func testDelegateCompletionWithErrorDoesNotEmitOne() {
        let tracker = UploadProgressTracker()
        var received: [Double] = []
        tracker.progressPublisher
            .dropFirst()
            .sink { received.append($0) }
            .store(in: &cancellables)

        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        tracker.urlSession(
            URLSession.shared,
            task: URLSession.shared.dataTask(with: URL(string: "https://example.com")!),
            didCompleteWithError: err
        )

        // Error path must NOT emit 1.0
        XCTAssertTrue(received.isEmpty || received.last != 1.0,
                      "must not emit 1.0 on error completion")
    }
}
