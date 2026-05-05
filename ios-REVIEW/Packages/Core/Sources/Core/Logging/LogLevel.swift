// §32 Logging strategy — LogLevel
// Phase 0 foundation

/// Severity levels mirroring OSLog / `os.Logger` conventions.
public enum LogLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    // MARK: Comparable support (debug < info < ... < critical)
    private var order: Int {
        switch self {
        case .debug:    return 0
        case .info:     return 1
        case .notice:   return 2
        case .warning:  return 3
        case .error:    return 4
        case .critical: return 5
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.order < rhs.order
    }
}
