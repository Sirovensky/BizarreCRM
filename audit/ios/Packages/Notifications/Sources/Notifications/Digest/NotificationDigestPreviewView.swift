import SwiftUI
import DesignSystem

// MARK: - DigestSummaryItem

/// A single category summary line in the digest preview.
public struct DigestSummaryItem: Identifiable, Sendable {
    public let id: String
    public let category: EventCategory
    public let count: Int
    public let label: String

    public init(category: EventCategory, count: Int) {
        self.id = category.rawValue
        self.category = category
        self.count = count
        self.label = "\(count) \(category.rawValue.lowercased())"
    }
}

// MARK: - NotificationDigestPreviewView

/// Glass-surfaced preview card: "Morning digest: 3 tickets, 2 SMS, 1 invoice paid".
public struct NotificationDigestPreviewView: View {

    let items: [DigestSummaryItem]
    let digestTime: DigestTime

    public init(items: [DigestSummaryItem], digestTime: DigestTime = .defaultMorning) {
        self.items = items
        self.digestTime = digestTime
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            headerRow
            Divider()
            itemList
            if !items.isEmpty {
                footerNote
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.bizarreOutline.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Morning Digest")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Delivered at \(digestTime.displayString)")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
    }

    // MARK: - Item list

    @ViewBuilder
    private var itemList: some View {
        if items.isEmpty {
            Text("No new notifications since last digest.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        } else {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                ForEach(items) { item in
                    HStack(spacing: BrandSpacing.sm) {
                        Circle()
                            .fill(Color.bizarreOrange)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(item.label)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text("\(item.count)")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerNote: some View {
        Text("Tap to open BizarreCRM and review all items.")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
    }

    // MARK: - A11y summary

    private var accessibilitySummary: String {
        guard !items.isEmpty else { return "Morning digest: no new notifications" }
        let summary = items.map { "\($0.count) \($0.category.rawValue.lowercased())" }.joined(separator: ", ")
        return "Morning digest: \(summary)"
    }
}

// MARK: - Font helpers

private extension Font {
    static func brandBodySmall() -> Font { .system(size: 13) }
    static func brandBodyLarge() -> Font { .system(size: 16) }
    static func brandLabelLarge() -> Font { .system(size: 15, weight: .semibold) }
    static func brandLabelSmall() -> Font { .system(size: 12) }
    static func brandHeadlineMedium() -> Font { .system(size: 20, weight: .semibold) }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NotificationDigestPreviewView(
        items: [
            DigestSummaryItem(category: .tickets, count: 3),
            DigestSummaryItem(category: .communications, count: 2),
            DigestSummaryItem(category: .billing, count: 1)
        ]
    )
    .padding()
    .background(Color.bizarreSurfaceBase)
}
#endif
