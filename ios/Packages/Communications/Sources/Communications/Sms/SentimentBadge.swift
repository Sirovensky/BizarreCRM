import SwiftUI
import DesignSystem

// MARK: - SentimentBadge
//
// §12.1 Sentiment badge — positive / neutral / negative.
// Server does not currently compute sentiment per-conversation.
// This badge is surfaced on conversations that expose a `sentiment`
// field once the server populates it. The enum is defined now so the
// UI is ready when the server-side NLP lands.
//
// Until `sentiment` is present in `SmsConversation`, callers pass nil
// and the badge renders nothing (graceful degradation).

public enum SmsSentiment: String, Sendable, Equatable {
    case positive = "positive"
    case neutral  = "neutral"
    case negative = "negative"
}

public struct SentimentBadge: View {
    public let sentiment: SmsSentiment?

    public init(sentiment: SmsSentiment?) {
        self.sentiment = sentiment
    }

    public var body: some View {
        if let s = sentiment {
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: icon(for: s))
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(s.rawValue.capitalized)
                    .font(.brandLabelSmall())
            }
            .foregroundStyle(color(for: s))
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .background(color(for: s).opacity(0.12), in: Capsule())
            .accessibilityLabel("Sentiment: \(s.rawValue)")
        }
    }

    private func icon(for sentiment: SmsSentiment) -> String {
        switch sentiment {
        case .positive: return "face.smiling"
        case .neutral:  return "minus.circle"
        case .negative: return "exclamationmark.circle"
        }
    }

    private func color(for sentiment: SmsSentiment) -> Color {
        switch sentiment {
        case .positive: return .green
        case .neutral:  return .bizarreOnSurfaceMuted
        case .negative: return .bizarreError
        }
    }
}
