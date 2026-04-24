import SwiftUI

// §30 — SemanticBadge
// Solid-filled capsule badge for the four semantic states:
// success / warning / danger / info.
// Mirrors StatusPill but is not tied to TicketStatus — suitable for any
// context (audit logs, invoice states, notification counts, etc.).

// MARK: - SemanticBadgeSeverity

/// The semantic intent of a badge.
public enum SemanticBadgeSeverity: Sendable, CaseIterable {
    case success
    case warning
    case danger
    case info

    /// Background fill color. Sourced from brand color tokens.
    public var backgroundColor: Color {
        switch self {
        case .success: return .bizarreSuccess
        case .warning: return .bizarreWarning
        case .danger:  return .bizarreDanger
        case .info:    return .bizarreInfo
        }
    }

    /// Foreground (text + icon) color that meets 4.5:1 contrast on the bg.
    public var foregroundColor: Color {
        switch self {
        case .success, .warning, .danger, .info: return .black
        }
    }

    /// VoiceOver role hint appended to the accessibility label.
    public var accessibilityHint: String {
        switch self {
        case .success: return "success"
        case .warning: return "warning"
        case .danger:  return "danger"
        case .info:    return "info"
        }
    }
}

// MARK: - SemanticBadge

/// Solid-fill capsule badge keyed by semantic severity.
///
/// Usage:
/// ```swift
/// SemanticBadge("Paid", severity: .success)
/// SemanticBadge("Overdue", severity: .danger)
/// SemanticBadge("3 alerts", severity: .warning)
/// SemanticBadge("Draft", severity: .info)
/// ```
public struct SemanticBadge: View {
    private let label: String
    private let severity: SemanticBadgeSeverity

    public init(_ label: String, severity: SemanticBadgeSeverity) {
        self.label = label
        self.severity = severity
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(severity.foregroundColor)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(severity.backgroundColor, in: Capsule())
            .accessibilityLabel("\(severity.accessibilityHint): \(label)")
    }
}
