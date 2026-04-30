import SwiftUI
import Core

/// Solid-filled pill — never glass, per §5.4 "USE/DON'T USE".
///
/// §26.6 — every pill carries an SF Symbol glyph in addition to color so
/// status conveyance is never color-alone. When the OS
/// `accessibilityDifferentiateWithoutColor` flag is set the glyph receives
/// an additional bold weight + capsule outline to maximise non-color signal.
public struct StatusPill: View {
    let label: String
    let hue: Hue

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    public init(_ label: String, hue: Hue) {
        self.label = label
        self.hue = hue
    }

    public init(_ status: TicketStatus) {
        self.label = status.displayName
        self.hue = Hue(status: status)
    }

    public enum Hue: Sendable {
        case intake, inProgress, awaiting, ready, completed, archived

        init(status: TicketStatus) {
            switch status {
            case .intake, .diagnosing:     self = .intake
            case .inProgress:              self = .inProgress
            case .awaitingParts:           self = .awaiting
            case .ready:                   self = .ready
            case .completed:               self = .completed
            case .archived:                self = .archived
            }
        }

        var bg: Color {
            switch self {
            case .intake:     return .bizarreSurface2
            case .inProgress: return .bizarreTeal
            case .awaiting:   return .bizarreWarning
            case .ready:      return .bizarreSuccess
            case .completed:  return .bizarreOrange
            case .archived:   return .bizarreOnSurfaceMuted
            }
        }

        var fg: Color {
            switch self {
            case .intake, .archived: return .bizarreOnSurface
            default:                 return .black
            }
        }

        /// Always-present SF Symbol so status conveyance is never color-alone.
        /// §26.6 — WCAG 1.4.1 Use of Color.
        var glyph: String {
            switch self {
            case .intake:     return "tray"
            case .inProgress: return "wrench.and.screwdriver.fill"
            case .awaiting:   return "hourglass"
            case .ready:      return "checkmark.seal.fill"
            case .completed:  return "flag.checkered"
            case .archived:   return "archivebox"
            }
        }
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: hue.glyph)
                .font(.system(size: 10, weight: differentiateWithoutColor ? .heavy : .semibold))
                .accessibilityHidden(true)
            Text(label)
                .font(.brandLabelSmall())
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .foregroundStyle(hue.fg)
        .background(hue.bg, in: Capsule())
        // §26.6 — under DifferentiateWithoutColor, add a 1pt outline so the
        // pill is distinguishable even when colors are remapped/inverted.
        .overlay(
            Capsule()
                .strokeBorder(
                    differentiateWithoutColor ? hue.fg.opacity(0.55) : Color.clear,
                    lineWidth: differentiateWithoutColor ? 1 : 0
                )
        )
        .accessibilityLabel("Status: \(label)")
    }
}
