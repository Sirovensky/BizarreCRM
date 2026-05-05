import Foundation
import AVFoundation
import Observation

// MARK: - SmsVoiceMemoRecorder

/// §12.2 Voice memo — records an AAC audio clip inline in the SMS thread.
///
/// The recording is stored in the OS temp directory and returned as a local
/// `URL` ready for `MmsUploadService.sendVoiceMemo(to:audioURL:)`.
///
/// Sovereignty: audio data uploaded only to tenant server; no third-party CDN.
///
/// Usage:
/// ```swift
/// let recorder = SmsVoiceMemoRecorder()
/// await recorder.requestPermission()
/// recorder.start()          // shows waveform / timer in UI
/// let url = recorder.stop() // returns temp file URL
/// ```
@MainActor
@Observable
public final class SmsVoiceMemoRecorder {

    public enum State: Equatable, Sendable {
        case idle
        case recording(seconds: Double)
        case done(URL)
        case failed(String)
        case permissionDenied
    }

    public private(set) var state: State = .idle

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var outputURL: URL?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var secondsRecorded: Double = 0

    /// Maximum recording duration — 5 minutes.
    public static let maxDurationSeconds: Double = 300

    public init() {}

    // MARK: - Public API

    public func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    public func start() {
        guard state == .idle else { return }
        Task { @MainActor in
            let granted = await requestPermission()
            guard granted else { state = .permissionDenied; return }
            do {
                try startRecordingEngine()
                secondsRecorded = 0
                state = .recording(seconds: 0)
                timerTask = Task { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(0.1))
                        secondsRecorded += 0.1
                        if secondsRecorded >= Self.maxDurationSeconds {
                            _ = stop()
                            return
                        }
                        if case .recording = self.state {
                            self.state = .recording(seconds: self.secondsRecorded)
                        }
                    }
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops recording and returns the file URL.
    @discardableResult
    public func stop() -> URL? {
        timerTask?.cancel()
        timerTask = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        guard let url = outputURL else {
            state = .idle
            return nil
        }
        file = nil
        outputURL = nil
        state = .done(url)
        return url
    }

    public func reset() {
        stop()
        state = .idle
        secondsRecorded = 0
        outputURL = nil
    }

    /// Returns a formatted elapsed-time string, e.g. "0:32".
    public var elapsedLabel: String {
        guard case .recording(let secs) = state else { return "0:00" }
        let total = Int(secs)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: - Private

    private func startRecordingEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm_\(UUID().uuidString).aac")
        outputURL = outURL

        let newEngine = AVAudioEngine()
        let inputNode = newEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // AAC settings
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let audioFile = try AVAudioFile(forWriting: outURL, settings: settings)
        file = audioFile

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            try? audioFile.write(from: buffer)
            _ = self  // retain in closure
        }

        try newEngine.start()
        engine = newEngine
    }
}
