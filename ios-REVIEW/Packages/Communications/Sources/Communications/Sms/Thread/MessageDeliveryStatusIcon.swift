import SwiftUI
import DesignSystem

// MARK: - MessageDeliveryStatusIcon
//
// §12.2 Delivery status icons per message — sent / delivered / failed / scheduled.
// Shown beneath outbound message bubbles to indicate carrier delivery state.
// Status values match server's SmsMessage.status field.

public struct MessageDeliveryStatusIcon: View {
    public let status: String?

    public init(status: String?) {
        self.status = status
    }

    public var body: some View {
        if let info = statusInfo {
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: info.icon)
                    .font(.system(size: 10, weight: .medium))
                    .accessibilityHidden(true)
                Text(info.label)
                    .font(.system(size: 10, weight: .regular))
            }
            .foregroundStyle(info.color)
            .accessibilityLabel("Message status: \(info.label)")
        }
    }

    private struct StatusInfo {
        let icon: String
        let label: String
        let color: Color
    }

    private var statusInfo: StatusInfo? {
        switch status?.lowercased() {
        case "sent":
            return StatusInfo(icon: "checkmark", label: "Sent", color: .bizarreOnSurfaceMuted)
        case "delivered":
            return StatusInfo(icon: "checkmark.circle.fill", label: "Delivered", color: .green)
        case "failed":
            return StatusInfo(icon: "exclamationmark.circle.fill", label: "Failed", color: .bizarreError)
        case "scheduled":
            return StatusInfo(icon: "clock", label: "Scheduled", color: .bizarreOrange)
        case "sending", "queued", "pending":
            return StatusInfo(icon: "ellipsis.circle", label: "Sending…", color: .bizarreOnSurfaceMuted)
        case "simulated":
            return StatusInfo(icon: "play.circle", label: "Simulated", color: .bizarreMagenta)
        default:
            return nil
        }
    }
}
