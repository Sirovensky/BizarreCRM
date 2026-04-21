import SwiftUI
import DesignSystem

// MARK: - BundledNotificationView

/// Expandable card for a coalesced `NotificationBundle`.
/// Reduce Motion: replaces spring animation with an instant transition.
/// A11y: announces bundle count and category name.
public struct BundledNotificationView: View {

    let bundle: NotificationBundle
    var onDismiss: ((String) -> Void)?

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(bundle: NotificationBundle, onDismiss: ((String) -> Void)? = nil) {
        self.bundle = bundle
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                expandedRows
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .accessibilityElement(children: isExpanded ? .contain : .ignore)
        .accessibilityLabel(accessibilityBundleLabel)
        .accessibilityHint(isExpanded ? "Tap header to collapse" : "Tap header to expand")
        .accessibilityIdentifier("bundle.\(bundle.category.rawValue)")
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: BrandSpacing.md) {
                categoryIcon
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(bundle.category.rawValue)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(summaryText)
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.brandLabelMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded rows

    @ViewBuilder
    private var expandedRows: some View {
        Divider()
            .padding(.horizontal, BrandSpacing.md)

        ForEach(bundle.items) { item in
            HStack(spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(item.title)
                        .font(.brandLabelMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(item.body)
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
                Spacer()
                PriorityBadge(item.priority, compact: true)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)

            if item.id != bundle.items.last?.id {
                Divider()
                    .padding(.horizontal, BrandSpacing.md)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var categoryIcon: some View {
        ZStack {
            Circle()
                .fill(Color.bizarreOrange.opacity(0.15))
            Image(systemName: bundle.category.iconName)
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)
        }
    }

    private var summaryText: String {
        "\(bundle.count) \(bundle.category.rawValue.lowercased()) notifications"
    }

    private var accessibilityBundleLabel: String {
        "\(bundle.count) \(bundle.category.rawValue) notifications bundled"
    }
}

// MARK: - EventCategory icon helper

private extension EventCategory {
    var iconName: String {
        switch self {
        case .tickets:        return "wrench.and.screwdriver"
        case .communications: return "message.fill"
        case .customers:      return "person.fill"
        case .billing:        return "creditcard.fill"
        case .appointments:   return "calendar.badge.clock"
        case .inventory:      return "shippingbox.fill"
        case .pos:            return "cart.fill"
        case .staff:          return "person.2.fill"
        case .marketing:      return "megaphone.fill"
        case .admin:          return "shield.fill"
        }
    }
}

// MARK: - brandBodySmall / brandLabelMedium helpers

private extension Font {
    static func brandBodySmall() -> Font { .system(size: 13) }
    static func brandLabelMedium() -> Font { .system(size: 14, weight: .medium) }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let items = (0..<3).map { i in
        GroupableNotification(
            id: "item-\(i)",
            event: .ticketAssigned,
            title: "Ticket #\(1000 + i) assigned",
            body: "iPhone 15 Pro screen repair",
            receivedAt: Date().addingTimeInterval(Double(-i) * 10),
            priority: .timeSensitive
        )
    }
    let bundle = NotificationBundle(
        id: "preview",
        category: .tickets,
        items: items,
        latestAt: Date()
    )
    return BundledNotificationView(bundle: bundle)
        .padding()
        .background(Color.bizarreSurfaceBase)
}
#endif
