import SwiftUI
import DesignSystem
import Networking

// MARK: - NotificationDetailSheet

/// Full-content drill-in sheet presented when the user taps a notification row.
///
/// Features:
/// - Liquid Glass chrome header with icon + title.
/// - Full message body with selectable text.
/// - Entity context chip (type + id) for deep-linking.
/// - Mark-read / Mark-unread toggle button.
/// - Dismiss via drag or the close button.
/// - iPhone + iPad: presented as `.sheet` with a medium + large detent on iPhone,
///   as a popover on iPad regular-width.
public struct NotificationDetailSheet: View {

    // MARK: - Inputs

    public let item: NotificationItem
    public var onMarkRead: ((Int64) async -> Void)?
    public var onMarkUnread: ((Int64) async -> Void)?
    public var onDismiss: (() -> Void)?

    // MARK: - Local state

    @State private var isMarkingRead: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - Init

    public init(
        item: NotificationItem,
        onMarkRead: ((Int64) async -> Void)? = nil,
        onMarkUnread: ((Int64) async -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.item = item
        self.onMarkRead = onMarkRead
        self.onMarkUnread = onMarkUnread
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                scrollContent
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                glassHeader
                    .padding(.top, BrandSpacing.sm)

                messageSection
                metadataSection
                Spacer(minLength: BrandSpacing.xxl)
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    // MARK: - Glass header

    private var glassHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.bizarreOrangeContainer.opacity(0.25))
                    .frame(width: 52, height: 52)
                Image(systemName: iconName(for: item.type))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.title ?? "Notification")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .fixedSize(horizontal: false, vertical: true)

                if let ts = item.createdAt {
                    Text(formattedDate(from: ts))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerA11yLabel)
    }

    // MARK: - Message section

    @ViewBuilder
    private var messageSection: some View {
        if let msg = item.message, !msg.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Details")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityAddTraits(.isHeader)

                Text(msg)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(BrandSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            }
        }
    }

    // MARK: - Metadata section

    @ViewBuilder
    private var metadataSection: some View {
        let hasEntity = item.entityType != nil || item.entityId != nil
        if hasEntity || !item.read {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Info")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    if let entityType = item.entityType {
                        metadataRow(
                            icon: "tag",
                            label: "Type",
                            value: entityType.capitalized
                        )
                        Divider().padding(.horizontal, BrandSpacing.md)
                    }
                    if let entityId = item.entityId {
                        metadataRow(
                            icon: "number",
                            label: "ID",
                            value: String(entityId)
                        )
                        if !item.read {
                            Divider().padding(.horizontal, BrandSpacing.md)
                        }
                    }
                    if !item.read {
                        metadataRow(
                            icon: "envelope.badge",
                            label: "Status",
                            value: "Unread"
                        )
                    }
                }
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            }
        }
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Spacer()

            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                onDismiss?()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("notif.detail.close")
        }

        ToolbarItem(placement: .primaryAction) {
            markReadButton
        }
    }

    @ViewBuilder
    private var markReadButton: some View {
        if isMarkingRead {
            ProgressView()
                .controlSize(.small)
        } else if item.read {
            Button {
                Task {
                    isMarkingRead = true
                    await onMarkUnread?(item.id)
                    isMarkingRead = false
                }
            } label: {
                Label("Mark unread", systemImage: "envelope.badge")
                    .font(.brandLabelLarge())
            }
            .tint(.bizarreTeal)
            .accessibilityIdentifier("notif.detail.markUnread")
        } else {
            Button {
                Task {
                    isMarkingRead = true
                    await onMarkRead?(item.id)
                    isMarkingRead = false
                }
            } label: {
                Label("Mark read", systemImage: "envelope.open")
                    .font(.brandLabelLarge())
            }
            .tint(.bizarreTeal)
            .accessibilityIdentifier("notif.detail.markRead")
        }
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

    private func formattedDate(from raw: String) -> String {
        let isoFull: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let isoBasic = ISO8601DateFormatter()
        let date = isoFull.date(from: raw) ?? isoBasic.date(from: raw)
        guard let date else { return raw }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private var headerA11yLabel: String {
        let status = item.read ? "Read" : "Unread"
        let title = item.title ?? "Notification"
        let time = item.createdAt.map { formattedDate(from: $0) } ?? ""
        return "\(status) notification: \(title), received \(time)"
    }
}

// MARK: - notificationDetailSheet modifier

public extension View {
    /// Presents a `NotificationDetailSheet` when `item` is non-nil.
    func notificationDetailSheet(
        item: Binding<NotificationItem?>,
        onMarkRead: ((Int64) async -> Void)? = nil,
        onMarkUnread: ((Int64) async -> Void)? = nil
    ) -> some View {
        sheet(item: item) { note in
            NotificationDetailSheet(
                item: note,
                onMarkRead: onMarkRead,
                onMarkUnread: onMarkUnread,
                onDismiss: { item.wrappedValue = nil }
            )
        }
    }
}
