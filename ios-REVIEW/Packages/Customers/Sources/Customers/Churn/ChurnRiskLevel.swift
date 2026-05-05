import Foundation

// MARK: - ChurnRiskLevel

/// §44.3 — Four-level risk classification derived from churn probability (0–100).
///
/// Thresholds:
///   low      0–24
///   medium  25–50
///   high    51–75
///   critical 76–100
public enum ChurnRiskLevel: String, Sendable, Equatable, CaseIterable, Codable {
    case low
    case medium
    case high
    case critical

    /// Derive risk level from a 0–100 probability integer.
    public init(probability: Int) {
        let clamped = max(0, min(100, probability))
        if clamped <= 24 {
            self = .low
        } else if clamped <= 50 {
            self = .medium
        } else if clamped <= 75 {
            self = .high
        } else {
            self = .critical
        }
    }

    public var label: String {
        switch self {
        case .low:      return "Low risk"
        case .medium:   return "Medium risk"
        case .high:     return "High risk"
        case .critical: return "Critical risk"
        }
    }

    public var icon: String {
        switch self {
        case .low:      return "checkmark.shield.fill"
        case .medium:   return "exclamationmark.triangle.fill"
        case .high:     return "xmark.shield.fill"
        case .critical: return "flame.fill"
        }
    }
}
