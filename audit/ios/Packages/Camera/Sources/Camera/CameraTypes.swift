import Foundation

// MARK: - PhotoFormat

/// Capture encoding format. Available on all platforms.
public enum PhotoFormat: Sendable {
    case heic
    case jpeg
}

// MARK: - CameraError

/// Domain errors raised by ``CameraService``. Available on all platforms so
/// unit tests can reference them without UIKit.
public enum CameraError: LocalizedError, Sendable {
    case notAuthorized
    case hardwareUnavailable
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Camera access is not authorized. Enable it in Settings."
        case .hardwareUnavailable:
            return "The camera hardware is unavailable on this device."
        case .captureFailed(let reason):
            return "Photo capture failed: \(reason)."
        }
    }
}
