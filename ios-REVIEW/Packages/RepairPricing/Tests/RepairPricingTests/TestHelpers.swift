import Foundation

/// Shared test error used across new stub API clients.
enum TestError: Error, LocalizedError {
    case forced, notImplemented
    var errorDescription: String? {
        switch self {
        case .forced: return "Forced test error"
        case .notImplemented: return "Not implemented in stub"
        }
    }
}
