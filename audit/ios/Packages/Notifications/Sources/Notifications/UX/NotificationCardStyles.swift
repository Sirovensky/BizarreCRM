import SwiftUI
import DesignSystem
import Networking

// MARK: - NotificationCardStyle

/// Visual variants for a notification card.
///
/// - `compact`  — single-line title + timestamp; used in Bundling / GroupBy headers.
/// - `expanded` — title + body + metadata row; the default list row.
/// - `grouped`  — compact header + N-item sub-list bubble; used by grouped stacks.
public enum NotificationCardStyle: Equatable, Sendable {
    case compact
    case expanded
    case grouped(count: Int)
}

// MARK: - NotificationCard

/// A Liquid-Glass-backed notification card that adapts its layout to
/// `NotificationCardStyle`. Call sites supply an `item`; the card handles
/// all visual variants internally.
///
/// iPhone + iPad: uses `BrandGlassContainer` so adjacent cards share a
/// sampling region and stay within the §30 glass budget.
public struct NotificationCard: View {

    // MARK: - Inputs

    public let item: NotificationItem
    public let style: NotificationCardStyle
    public var onTap: (() -> Void)?

    // MARK: - Init

    public init(
        item: NotificationItem,
        style: NotificationCardStyle = .expanded,
        onTap: (() -> Void)? = nil
    ) {
        self.item = item
        self.style = style
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        switch style {
        case .compact:
            compactLayout
        case .expanded:
            expandedLayout
        case .grouped(let count):
            groupedLayout(count: count)
        }
    }

    // MARK: - Compact

    private var compactLayout: some View {
        HStack(spacing: BrandSpacing.sm) {
            eventIcon
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(item.title ?? "Notification")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            timestampLabel
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .unreadDot(show: !item.read)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compactA11yLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Expanded

    private var expandedLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            eventIcon
                .font(.system(size: 18, weight: .medium))
                .frame(width: 28)
                .padding(.top, BrandSpacing.xxs)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.title ?? "Notification")
                    .font(.brandBodyLarge())
                    .fontWeight(item.read ? .regular : .semibold)
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)

                if let msg = item.message, !msg.isEmpty {
                    Text(msg)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(3)
                }

                metadataRow
            }

            unreadIndicator
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(expandedA11yLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Grouped

    private func groupedLayout(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            HStack(spacing: BrandSpacing.sm) {
                eventIcon
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(item.title ?? "Notification")
                    .font(.brandBodyLarge())
                    .fontWeight(.semibold)
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                BrandGlassBadge("+\(count - 1)", variant: .regular, tint: .bizarreOrange)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)

            if let msg = item.message, !msg.isEmpty {
                Divider()
                    .padding(.horizontal, BrandSpacing.md)
                    .foregroundStyle(.bizarreOutline)

                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.xs)
            }
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(groupedA11yLabel(count: count))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Shared sub-views

    private var eventIcon: some View {
        Image(systemName: iconName(for: item.type))
            .foregroundStyle(item.read ? .bizarreOnSurfaceMuted : .bizarreOrange)
    }

    private var metadataRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            if let ts = item.createdAt {
                Text(relativeTime(from: ts))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let entityType = item.entityType {
                Text(entityType.capitalized)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreTeal)
                    .lineLimit(1)
            }
        }
    }

    private var timestampLabel: some View {
        Group {
            if let ts = item.createdAt {
                Text(relativeTime(from: ts))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    @ViewBuilder
    private var unreadIndicator: some View {
        if !item.read {
            Circle()
                .fill(Color.bizarreMagenta)
                .frame(width: 8, height: 8)
                .padding(.top, BrandSpacing.xs)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Glass background

    private var cardBackground: some ShapeStyle {
        if item.read {
            return AnyShapeStyle(Color.bizarreSurface1)
        } else {
            return AnyShapeStyle(Color.bizarreOrangeContainer.opacity(0.18))
        }
    }

    // MARK: - Accessibility labels

    private var compactA11yLabel: String {
        let status = item.read ? "Read" : "Unread"
        let title = item.title ?? "Notification"
        let time = item.createdAt.map { relativeTime(from: $0) } ?? ""
        return "\(status). \(title). \(time)"
    }

    private var expandedA11yLabel: String {
        let status = item.read ? "Read" : "Unread"
        let title = item.title ?? "Notification"
        let msg = item.message ?? ""
        let time = item.createdAt.map { relativeTime(from: $0) } ?? ""
        return "\(status). \(title). \(msg). \(time)"
    }

    private func groupedA11yLabel(count: Int) -> String {
        let title = item.title ?? "Notification"
        return "Group of \(count) notifications. \(title)"
    }

    // MARK: - Helpers

    private func iconName(for type: String?) -> String {
        let t = type?.lowercased() ?? ""
        if t.contains("ticket")             { return "wrench.and.screwdriver" }
        if t.contains("sms")                { return "message" }
        if t.contains("invoice") || t.contains("estimate") { return "doc.text" }
        if t.contains("payment") || t.contains("refund")   { return "creditcard" }
        if t.contains("appoint")            { return "calendar" }
        if t.contains("mention")            { return "at" }
        if t.contains("inventory")          { return "shippingbox" }
        if t.contains("security")           { return "lock.shield" }
        if t.contains("backup")             { return "externaldrive" }
        return "bell"
    }

    private func relativeTime(from raw: String) -> String {
        let isoFull: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let isoBasic = ISO8601DateFormatter()
        let sql: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = TimeZone(identifier: "UTC")
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()
        let date = isoFull.date(from: raw) ?? isoBasic.date(from: raw) ?? sql.date(from: raw)
        guard let date else { return String(raw.prefix(16)) }
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:       return "just now"
        case ..<3600:     return "\(seconds / 60)m ago"
        case ..<86_400:   return "\(seconds / 3600)h ago"
        case ..<172_800:  return "yesterday"
        case ..<604_800:  return "\(seconds / 86_400)d ago"
        default:
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            return df.string(from: date)
        }
    }
}

// MARK: - UnreadDot view modifier (private)

private struct UnreadDotModifier: ViewModifier {
    let show: Bool
    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if show {
                Circle()
                    .fill(Color.bizarreMagenta)
                    .frame(width: 7, height: 7)
                    .offset(x: 4, y: -4)
                    .accessibilityHidden(true)
            }
        }
    }
}

private extension View {
    func unreadDot(show: Bool) -> some View {
        modifier(UnreadDotModifier(show: show))
    }
}
