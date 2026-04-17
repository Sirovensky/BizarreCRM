import SwiftUI
import Core

/// Solid-filled pill — never glass, per §5.4 "USE/DON'T USE".
public struct StatusPill: View {
    let label: String
    let hue: Hue

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
    }

    public var body: some View {
        Text(label)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            .foregroundStyle(hue.fg)
            .background(hue.bg, in: Capsule())
            .accessibilityLabel("Status: \(label)")
    }
}
