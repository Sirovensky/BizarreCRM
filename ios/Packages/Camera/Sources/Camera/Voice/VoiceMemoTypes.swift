import Foundation

// MARK: - VoiceMemoError

/// Domain errors raised by the voice memo subsystem. Platform-independent so
/// tests can reference them without UIKit / AVFoundation stubs.
public enum VoiceMemoError: LocalizedError, Sendable {
    case notAuthorized
    case alreadyRecording
    case notRecording
    case setupFailed(String)
    case playbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Microphone access is required to record voice memos. Enable it in Settings."
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "No recording is currently in progress."
        case .setupFailed(let reason):
            return "Recording setup failed: \(reason)."
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)."
        }
    }
}

// MARK: - VoiceMemoState

/// Observable state for the voice memo recording lifecycle.
public enum VoiceMemoState: Equatable, Sendable {
    case idle
    case requesting
    case recording(startedAt: Date)
    case stopping
    case saved(url: URL)
    case failed(message: String)

    public static func == (lhs: VoiceMemoState, rhs: VoiceMemoState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.requesting, .requesting): return true
        case (.recording(let a), .recording(let b)): return a == b
        case (.stopping, .stopping): return true
        case (.saved(let a), .saved(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}
