import SwiftUI
import DesignSystem

/// Solid pill badge for campaign status. Never uses glass (content area).
public struct CampaignStatusBadge: View {
    let status: CampaignStatus

    public init(_ status: CampaignStatus) {
        self.status = status
    }

    private var bg: Color {
        switch status {
        case .draft:      return .bizarreSurface2
        case .scheduled:  return .bizarreTeal
        case .sending:    return .bizarreWarning
        case .sent:       return .bizarreSuccess
        case .failed:     return .bizarreError
        }
    }

    private var fg: Color {
        switch status {
        case .draft:  return .bizarreOnSurface
        case .failed: return .white
        default:      return .black
        }
    }

    public var body: some View {
        Text(status.displayName)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .accessibilityLabel("Status: \(status.displayName)")
    }
}
