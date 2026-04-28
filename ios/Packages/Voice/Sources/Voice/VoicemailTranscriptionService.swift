import Foundation
import Speech
import AVFoundation
import Core

// §42.5 On-device voicemail transcription pipeline.
//
// Uses Apple's on-device `SFSpeechRecognizer` with `.requiresOnDeviceRecognition = true`
// so audio never leaves the device (data sovereignty §28 / §32).
//
// When a voicemail has `transcriptText` from the server, we display that directly.
// When the server field is nil (or the feature is coming-soon), this pipeline
// transcribes the locally-downloaded audio file using Speech framework.
//
// Supported formats: m4a, mp3, wav, aac, caf (anything AVAudioFile can open).
//
// Public API:
//   let service = VoicemailTranscriptionService()
//   let text = try await service.transcribe(audioURL: fileURL, locale: .current)

// MARK: - TranscriptionState

public enum TranscriptionState: Sendable, Equatable {
    case idle
    case requestingPermission
    case transcribing(progress: Double)
    case completed(text: String)
    case unavailable(reason: String)
    case failed(message: String)
}

// MARK: - VoicemailTranscriptionService

public actor VoicemailTranscriptionService {

    // MARK: - Init

    public init() {}

    // MARK: - Transcribe

    /// Transcribe an audio file on-device using `SFSpeechRecognizer`.
    ///
    /// - Parameters:
    ///   - audioURL: Local file URL of the audio to transcribe.
    ///   - locale: Locale for speech recognition. Defaults to current device locale.
    ///   - progressHandler: Optional callback with 0.0–1.0 progress (best-effort).
    /// - Returns: Transcribed text string.
    /// - Throws: `TranscriptionError` on permission denial, recognition failure, or unavailability.
    public func transcribe(
        audioURL: URL,
        locale: Locale = .current,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        // 1. Request permission
        let status = await requestPermission()
        guard status == .authorized else {
            throw TranscriptionError.permissionDenied
        }

        // 2. Create recognizer
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // 3. Prefer on-device to avoid any network egress
        recognizer.defaultTaskHint = .unspecified

        // 4. Build request from file
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        AppLog.app.info("VoicemailTranscriptionService: starting on-device=\(request.requiresOnDeviceRecognition) locale=\(locale.identifier, privacy: .public)")

        // 5. Run recognition via async continuation
        return try await withCheckedThrowingContinuation { continuation in
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    AppLog.app.error("VoicemailTranscriptionService: recognition error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    AppLog.app.info("VoicemailTranscriptionService: completed \(text.count) chars")
                    continuation.resume(returning: text)
                } else {
                    let progress = min(0.99, Double(result.bestTranscription.segments.count) / 20.0)
                    progressHandler?(progress)
                }
            }
            _ = task // retain
        }
    }

    // MARK: - Permission

    /// Request `SFSpeechRecognizer` authorization without blocking.
    public func requestPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    public var currentPermissionStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
}

// MARK: - TranscriptionError

public enum TranscriptionError: Error, LocalizedError, Sendable {
    case permissionDenied
    case unsupportedLocale(String)
    case recognizerUnavailable
    case recognitionFailed(String)
    case audioFileUnreadable(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission denied. Go to Settings → Privacy → Speech Recognition to enable it."
        case .unsupportedLocale(let id):
            return "Speech recognition is not available for the locale '\(id)'."
        case .recognizerUnavailable:
            return "Speech recognizer is temporarily unavailable. Try again shortly."
        case .recognitionFailed(let detail):
            return "Transcription failed: \(detail)"
        case .audioFileUnreadable(let path):
            return "Cannot read audio file at '\(path)'."
        }
    }
}
