import SwiftUI
import DesignSystem

// MARK: - OffHoursIndicator
//
// §12.2 Off-hours auto-reply indicator.
//
// Shown in the SMS thread composer area when the tenant's auto-responder is
// active AND the current time falls within a quiet-hours window.  The banner
// informs the sender that an auto-reply will fire; it does NOT block sending.
//
// Placement: between the message list and the composer bar in `SmsThreadView`.

public struct OffHoursIndicator: View {
    public let autoResponderName: String

    public init(autoResponderName: String) {
        self.autoResponderName = autoResponderName
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.bizarreOrange)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text("Auto-reply is active: \"\(autoResponderName)\"")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.xs)
        .background(.ultraThinMaterial, in: Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Off-hours auto-reply is active: \(autoResponderName)")
    }
}

// MARK: - OffHoursAutoReplyChecker
//
// Pure logic: given a list of `AutoResponderRule`s and a reference date,
// returns the first rule that is currently active (enabled + within quiet hours).

public struct OffHoursAutoReplyChecker: Sendable {
    public static func activeRule(
        from rules: [AutoResponderRule],
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> AutoResponderRule? {
        rules.first { $0.enabled && $0.isActive(at: date) }
    }
}
