import Foundation
import Observation
import Core

// MARK: - VoiceMemoViewModel

/// `@Observable` view-model managing the voice memo recording lifecycle.
///
/// Drives ``VoiceMemoView`` via observable state transitions.
///
/// Dependency injection: callers supply a `RecorderProtocol` — real code passes
/// `VoiceMemoRecorder()`, tests pass a `MockVoiceMemoRecorder`.
///
/// State machine:
/// ```
/// idle → requesting → recording → stopping → saved
///                   ↘ failed
/// ```
@Observable
@MainActor
public final class VoiceMemoViewModel {

    // MARK: - Types

    /// Abstraction over `VoiceMemoRecorder` for testability.
    public protocol RecorderProtocol: AnyObject, Sendable {
        func authorize() async throws -> Bool
        func startRecording(maxDuration: TimeInterval) async throws -> URL
        func stopRecording() async throws -> URL
    }

    // MARK: - State

    public private(set) var recordingState: VoiceMemoState = .idle
    public private(set) var elapsedSeconds: Int = 0

    // MARK: - Configuration

    /// Maximum recording duration in seconds. Enforced by the recorder.
    public let maxDuration: TimeInterval

    // MARK: - Private

    private let recorder: RecorderProtocol
    private var elapsedTimer: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - recorder: The recorder to use. Defaults to `VoiceMemoRecorder()`.
    ///   - maxDuration: Time-based stop limit. Defaults to 120 s.
    public init(
        recorder: RecorderProtocol,
        maxDuration: TimeInterval = 120
    ) {
        self.recorder = recorder
        self.maxDuration = maxDuration
    }

    // MARK: - Actions

    /// Begin recording. Requests microphone permission first if needed.
    public func startRecording() async {
        guard case .idle = recordingState else { return }

        recordingState = .requesting
        do {
            _ = try await recorder.authorize()
        } catch {
            recordingState = .failed(message: error.localizedDescription)
            return
        }

        do {
            _ = try await recorder.startRecording(maxDuration: maxDuration)
            elapsedSeconds = 0
            recordingState = .recording(startedAt: Date())
            startElapsedTimer()
        } catch {
            recordingState = .failed(message: error.localizedDescription)
        }
    }

    /// Stop an in-progress recording and save the result.
    public func stopRecording() async {
        guard case .recording = recordingState else { return }

        recordingState = .stopping
        stopElapsedTimer()

        do {
            let url = try await recorder.stopRecording()
            recordingState = .saved(url: url)
            AppLog.ui.info("VoiceMemoViewModel: saved to \(url.lastPathComponent, privacy: .public)")
        } catch {
            recordingState = .failed(message: error.localizedDescription)
        }
    }

    /// Discard the current saved memo and reset to idle.
    /// No-op when not in `.saved` state.
    public func discard() {
        if case .saved(let url) = recordingState {
            try? FileManager.default.removeItem(at: url)
        }
        reset()
    }

    /// Reset to idle so the user can record again.
    public func reset() {
        stopElapsedTimer()
        elapsedSeconds = 0
        recordingState = .idle
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        // Task inherits @MainActor isolation — safe to mutate self directly.
        elapsedTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { break }
                self.elapsedSeconds += 1
                // Auto-transition when the elapsed count hits the configured limit.
                if Double(self.elapsedSeconds) >= self.maxDuration {
                    await self.stopRecording()
                }
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = nil
    }
}
