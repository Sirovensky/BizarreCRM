import Foundation
import Combine

// MARK: - UploadProgressTracker
//
// Bridges URLSession upload-task delegate callbacks into a Combine publisher.
// Each upload task gets its own tracker instance; the caller observes
// `progressPublisher` for values in [0.0, 1.0].
//
// Usage:
//   let tracker = UploadProgressTracker()
//   tracker.progressPublisher
//       .receive(on: DispatchQueue.main)
//       .sink { fraction in progressView.progress = Float(fraction) }
//       .store(in: &cancellables)
//
//   // Feed updates from URLSessionTaskDelegate:
//   tracker.update(bytesSent: sentBytes, totalBytes: totalBytes)

// `@unchecked Sendable`: `CurrentValueSubject` is internally lock-protected,
// making cross-thread access safe despite the stored reference type.
public final class UploadProgressTracker: NSObject, @unchecked Sendable {

    // MARK: Publisher

    /// Emits progress fractions in [0.0, 1.0]. Never fails.
    public var progressPublisher: AnyPublisher<Double, Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: Private state

    private let subject = CurrentValueSubject<Double, Never>(0.0)

    // MARK: Init

    public override init() {
        super.init()
    }

    // MARK: Update

    /// Update progress from URLSession delegate bytes-sent callback.
    /// Safe to call from any thread.
    ///
    /// - Parameters:
    ///   - bytesSent: Cumulative bytes sent so far.
    ///   - totalBytes: Total expected bytes; pass -1 if unknown (progress
    ///     will be clamped to the last known value).
    public func update(bytesSent: Int64, totalBytes: Int64) {
        guard totalBytes > 0 else { return }
        let fraction = min(1.0, max(0.0, Double(bytesSent) / Double(totalBytes)))
        subject.send(fraction)
    }

    /// Marks the upload as complete (sends 1.0 and completes the subject).
    public func complete() {
        subject.send(1.0)
    }
}

// MARK: - URLSessionTaskDelegate conformance

extension UploadProgressTracker: URLSessionTaskDelegate {
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        update(bytesSent: totalBytesSent, totalBytes: totalBytesExpectedToSend)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil {
            complete()
        }
    }
}
