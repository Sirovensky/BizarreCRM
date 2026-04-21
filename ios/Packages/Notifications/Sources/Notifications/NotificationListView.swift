import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

@MainActor
@Observable
public final class NotificationListViewModel {
    public private(set) var items: [NotificationItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var successBanner: String?
    /// Exposed for `StalenessIndicator` chip in toolbar.
    public private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cachedRepo: NotificationCachedRepository?

    public init(api: APIClient, cachedRepo: NotificationCachedRepository? = nil) {
        self.api = api
        self.cachedRepo = cachedRepo
    }

    public var unreadCount: Int { items.filter { !$0.read }.count }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                items = try await repo.listNotifications()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                items = try await api.listNotifications()
            }
        } catch {
            AppLog.ui.error("Notifications load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func forceRefresh() async {
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                items = try await repo.forceRefresh()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                items = try await api.listNotifications()
            }
        } catch {
            AppLog.ui.error("Notifications force-refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Flip a single row to read. Optimistic UI — swap locally first so
    /// swipe action feels instant, revert on server failure.
    public func markRead(id: Int64) async {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let previous = items[idx]
        items[idx] = previous.flippedRead()
        do {
            _ = try await api.markNotificationRead(id: id)
        } catch {
            // Revert — server couldn't mark; show an error toast.
            items[idx] = previous
            errorMessage = "Couldn't mark as read. Please try again."
        }
    }

    public func markAllRead() async {
        let previous = items
        items = items.map { $0.flippedReadForced() }
        do {
            let resp = try await api.markAllNotificationsRead()
            successBanner = "Marked \(resp.updated ?? previous.filter { !$0.read }.count) as read"
        } catch {
            items = previous
            errorMessage = "Couldn't mark all as read."
        }
    }

    public func dismissBanner() { successBanner = nil }
}

/// Helper: make a copy of the row with `read` flipped. `NotificationItem`
/// is Decodable-only so we reconstruct via the `isRead` field; keeping
/// the model pure means no mutable bleed into view code.
private extension NotificationItem {
    func flippedRead() -> NotificationItem {
        .init(
            id: id, type: type, title: title, message: message,
            entityType: entityType, entityId: entityId,
            isRead: 1, createdAt: createdAt
        )
    }

    /// Force-read even if already read (idempotent for mark-all).
    func flippedReadForced() -> NotificationItem {
        .init(
            id: id, type: type, title: title, message: message,
            entityType: entityType, entityId: entityId,
            isRead: 1, createdAt: createdAt
        )
    }
}

public struct NotificationListView: View {
    @State private var vm: NotificationListViewModel

    public init(api: APIClient, cachedRepo: NotificationCachedRepository? = nil) {
        _vm = State(wrappedValue: NotificationListViewModel(api: api, cachedRepo: cachedRepo))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
            }
            if vm.unreadCount > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") { Task { await vm.markAllRead() } }
                        .font(.brandLabelLarge())
                        .accessibilityIdentifier("notifications.markAllRead")
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.forceRefresh() }
        .overlay(alignment: .top) {
            if let msg = vm.successBanner {
                Text(msg)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
                    .brandGlass(.regular, tint: .bizarreSuccess)
                    .padding(.top, BrandSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        vm.dismissBanner()
                    }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if let err = vm.errorMessage { errorPane(err) }
        else if vm.items.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "notifications")
        } else if vm.items.isEmpty {
            emptyState(icon: "bell.slash", text: "You're all caught up")
        } else {
            List {
                ForEach(vm.items) { note in
                    Row(note: note)
                        .listRowBackground(Color.bizarreSurface1)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !note.read {
                                Button {
                                    Task { await vm.markRead(id: note.id) }
                                } label: {
                                    Label("Mark read", systemImage: "envelope.open")
                                }
                                .tint(.bizarreTeal)
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func errorPane(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load notifications").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(text).font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct Row: View {
        let note: NotificationItem

        var body: some View {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                Image(systemName: iconForType(note.type))
                    .foregroundStyle(note.read ? .bizarreOnSurfaceMuted : .bizarreOrange)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(note.title ?? "Notification")
                        .font(.brandBodyLarge())
                        .fontWeight(note.read ? .regular : .semibold)
                        .foregroundStyle(.bizarreOnSurface)
                    if let msg = note.message, !msg.isEmpty {
                        Text(msg).font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(3)
                    }
                    if let ts = note.createdAt {
                        Text(Self.relative(from: ts))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                if !note.read {
                    Circle()
                        .fill(Color.bizarreMagenta)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: note))
        }

        /// Pulled out of the inline modifier because a 3-way string
        /// concatenation inside `.accessibilityLabel` hits the SwiftUI
        /// type-checker's complexity budget.
        static func a11y(for note: NotificationItem) -> String {
            let status = note.read ? "Read" : "Unread"
            let title = note.title ?? "Notification"
            let msg = note.message ?? ""
            return "\(status). \(title). \(msg)"
        }

        private func iconForType(_ type: String?) -> String {
            switch type?.lowercased() {
            case let t? where t.contains("ticket"):   return "wrench.and.screwdriver"
            case let t? where t.contains("sms"):      return "message"
            case let t? where t.contains("invoice"):  return "doc.text"
            case let t? where t.contains("lead"):     return "sparkles"
            case let t? where t.contains("appoint"):  return "calendar"
            case let t? where t.contains("inventory"):return "shippingbox"
            default: return "bell"
            }
        }

        /// Parse ISO-8601 / SQLite datetime strings and render a short
        /// relative time ("3m ago", "yesterday", "Apr 14"). Falls back to
        /// the raw first 16 chars on parse failure so we don't hide data.
        static func relative(from raw: String) -> String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let sql = DateFormatter()
            sql.dateFormat = "yyyy-MM-dd HH:mm:ss"
            sql.timeZone = TimeZone(identifier: "UTC")
            sql.locale = Locale(identifier: "en_US_POSIX")

            let date = iso.date(from: raw)
                ?? ISO8601DateFormatter().date(from: raw)
                ?? sql.date(from: raw)

            guard let date else { return String(raw.prefix(16)) }

            let seconds = Int(Date().timeIntervalSince(date))
            switch seconds {
            case ..<60:     return "just now"
            case ..<3600:   return "\(seconds / 60)m ago"
            case ..<86_400: return "\(seconds / 3600)h ago"
            case ..<172_800: return "yesterday"
            case ..<604_800: return "\(seconds / 86_400)d ago"
            default:
                let df = DateFormatter()
                df.dateFormat = "MMM d"
                return df.string(from: date)
            }
        }
    }
}
