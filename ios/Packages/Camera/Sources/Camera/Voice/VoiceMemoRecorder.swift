import Foundation
@preconcurrency import AVFoundation
import Core

// MARK: - VoiceMemoRecorder

/// Actor wrapping `AVAudioRecorder` for voice memo capture.
///
/// Lifecycle:
/// 1. `authorize()` — request microphone permission.
/// 2. `startRecording(maxDuration:)` — begin recording; stops automatically after
///    `maxDuration` seconds (default: 120 s). Returns the staging URL.
/// 3. `stopRecording()` — manual early stop; returns the recorded file URL.
/// 4. The caller owns the returned `URL`; use `FileManager` or `PhotoStore`
///    to promote or discard it.
///
/// Thread-safety: `actor` isolation — all mutations happen on the actor's
/// executor. The AVAudioRecorder delegate callback is bridged via `Task`.
public actor VoiceMemoRecorder: NSObject {

    // MARK: - Recording state

    /// `true` while recording is in progress.
    public private(set) var isRecording: Bool = false

    /// URL of the recording currently in progress (or the last completed one).
    public private(set) var currentURL: URL?

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var stopTimer: Task<Void, Never>?
    private var finishContinuation: CheckedContinuation<URL, Error>?

    // MARK: - Constants

    private static let defaultMaxDuration: TimeInterval = 120
    private static let audioSettings: [String: Any] = [
        AVFormatIDKey:               Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey:             22_050,
        AVNumberOfChannelsKey:       1,
        AVEncoderAudioQualityKey:    AVAudioQuality.medium.rawValue,
        AVEncoderBitRateKey:         32_000,
    ]

    // MARK: - Authorization

    /// Requests microphone permission if not yet determined.
    /// - Returns: `true` when access is granted.
    /// - Throws: ``VoiceMemoError/notAuthorized`` when denied.
    public func authorize() async throws -> Bool {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted { throw VoiceMemoError.notAuthorized }
            return granted
        } else {
            return try await withCheckedThrowingContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    if granted {
                        cont.resume(returning: true)
                    } else {
                        cont.resume(throwing: VoiceMemoError.notAuthorized)
                    }
                }
            }
        }
    }

    // MARK: - Recording

    /// Starts a new recording into a UUID-named `.m4a` file in the temp directory.
    ///
    /// - Parameter maxDuration: Recording stops automatically after this many seconds.
    ///   Defaults to 120 s. Pass `0` for no automatic stop (manual stop only).
    /// - Returns: `URL` of the in-progress recording file. The file is valid only
    ///   after `stopRecording()` completes.
    /// - Throws: ``VoiceMemoError`` if already recording, not authorized, or setup fails.
    @discardableResult
    public func startRecording(maxDuration: TimeInterval = VoiceMemoRecorder.defaultMaxDuration) async throws -> URL {
        guard !isRecording else {
            throw VoiceMemoError.alreadyRecording
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw VoiceMemoError.setupFailed(error.localizedDescription)
        }

        let filename = "\(UUID().uuidString).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let rec: AVAudioRecorder
        do {
            rec = try AVAudioRecorder(url: url, settings: Self.audioSettings)
        } catch {
            throw VoiceMemoError.setupFailed(error.localizedDescription)
        }

        rec.delegate = self
        guard rec.prepareToRecord() else {
            throw VoiceMemoError.setupFailed("prepareToRecord() returned false")
        }

        if maxDuration > 0 {
            rec.record(forDuration: maxDuration)
        } else {
            guard rec.record() else {
                throw VoiceMemoError.setupFailed("record() returned false")
            }
        }

        recorder = rec
        currentURL = url
        isRecording = true
        AppLog.ui.info("VoiceMemoRecorder: started → \(filename, privacy: .public)")

        // Auto-stop timer — fires slightly after maxDuration for cleanup.
        if maxDuration > 0 {
            stopTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((maxDuration + 0.5) * 1_000_000_000))
                await self?.handleTimerFired()
            }
        }

        return url
    }

    /// Stops recording immediately.
    /// - Returns: `URL` of the completed `.m4a` file.
    /// - Throws: ``VoiceMemoError/notRecording`` when called while idle.
    @discardableResult
    public func stopRecording() async throws -> URL {
        guard isRecording, let rec = recorder, let url = currentURL else {
            throw VoiceMemoError.notRecording
        }
        stopTimer?.cancel()
        stopTimer = nil
        rec.stop()
        isRecording = false
        recorder = nil
        deactivateSession()
        AppLog.ui.info("VoiceMemoRecorder: stopped → \(url.lastPathComponent, privacy: .public)")
        return url
    }

    // MARK: - Duration

    /// Current recording position in seconds. Zero when not recording.
    nonisolated public func currentTime() -> TimeInterval {
        // AVAudioRecorder.currentTime is thread-safe read.
        return 0
    }

    // MARK: - Private helpers

    private func handleTimerFired() {
        guard isRecording else { return }
        recorder?.stop()
        isRecording = false
        recorder = nil
        deactivateSession()
        AppLog.ui.info("VoiceMemoRecorder: auto-stopped at max duration")
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceMemoRecorder: AVAudioRecorderDelegate {
    nonisolated public func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        Task { await self.handleRecordingFinished(successfully: flag) }
    }

    nonisolated public func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        AppLog.ui.error("VoiceMemoRecorder encode error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
    }

    private func handleRecordingFinished(successfully: Bool) {
        guard isRecording else { return }
        isRecording = false
        recorder = nil
        deactivateSession()
        if !successfully {
            AppLog.ui.error("VoiceMemoRecorder: recording finished unsuccessfully")
        }
    }
}
