import SwiftUI
import DesignSystem

// MARK: - ReadReceiptView
//
// §12.2 Read receipts — display a "Read" indicator under the last outbound
// message when the server sends `read_at` on a message.
//
// Server support is conditional: `SmsMessage.readAt` is decoded when present.
// When nil (server does not support) no indicator is shown — graceful fallback.
//
// Usage:
//   ReadReceiptView(readAt: message.readAt)

public struct ReadReceiptView: View {
    public let readAt: String?

    public init(readAt: String?) {
        self.readAt = readAt
    }

    private var formattedDate: String? {
        guard let rawDate = readAt else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: rawDate)
              ?? ISO8601DateFormatter().date(from: rawDate) else { return rawDate }
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    public var body: some View {
        if let time = formattedDate {
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.bizarrePrimary)
                Text("Read \(time)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Message read at \(time)")
            .accessibilityAddTraits(.isStaticText)
        }
    }
}
