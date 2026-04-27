import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

// MARK: - NotificationListPolishedView

/// §13 polished notification list.
///
/// Features:
/// - Filter chips: All / Unread / type chips (Tickets, SMS, Invoices, …)
/// - Group-by-day headers with glass style
/// - Swipe-to-mark-read on each row
/// - Mark-all-read glass toolbar button
/// - "All caught up" illustrated empty state
/// - iPhone + iPad (sidebar navigation on regular width)
public struct NotificationListPolishedView: View {

    @State private var vm: NotificationListPolishedViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.openURL) private var openURL

    public init(api: APIClient, cachedRepo: NotificationCachedRepository? = nil) {
        _vm = State(
            wrappedValue: NotificationListPolishedViewModel(api: api, cachedRepo: cachedRepo)
        )
    }

    public var body: some View {
        Group {
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.forceRefresh() }
        .overlay(alignment: .top) { successBannerOverlay }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChipsBar
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.xs)
                    mainContent
                }
            }
            .navigationTitle("Notifications")
            .toolbar { toolbarItems }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { vm.activeFilter },
                set: { if let f = $0 { vm.setFilter(f) } }
            )) {
                Section("Filter") {
                    ForEach(NotificationFilterChip.primary) { chip in
                        Label(chip.label, systemImage: chipIcon(chip))
                            .tag(chip)
                            .accessibilityLabel(chip.label)
                    }
                }
                Section("Type") {
                    ForEach(NotificationFilterChip.typeChips) { chip in
                        Label(chip.label, systemImage: chipIcon(chip))
                            .tag(chip)
                            .accessibilityLabel(chip.label)
                            .hoverEffect(.highlight)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
            .navigationTitle("Filter")
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                mainContent
            }
            .navigationTitle("Notifications")
            .toolbar { toolbarItems }
        }
    }

    // MARK: - Filter chips bar (iPhone)

    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(
                    [NotificationFilterChip.all, .unread] + NotificationFilterChip.typeChips
                ) { chip in
                    chipButton(chip)
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
    }

    @ViewBuilder
    private func chipButton(_ chip: NotificationFilterChip) -> some View {
        let isActive = vm.activeFilter == chip
        Button {
            vm.setFilter(chip)
        } label: {
            Text(chip.label)
                .font(.brandLabelLarge())
                .foregroundStyle(isActive ? .white : .bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .background {
                    if isActive {
                        Capsule().fill(Color.bizarreOrange)
                    } else {
                        Capsule().fill(Color.bizarreSurface2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityIdentifier("notif.filter.\(chip.id)")
    }

    // MARK: - Toolbar items

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
        if vm.hasUnread {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.markAllRead() }
                } label: {
                    Label("Mark all read", systemImage: "envelope.open")
                        .labelStyle(.titleAndIcon)
                        .font(.brandLabelLarge())
                }
                .tint(.bizarreTeal)
                .accessibilityIdentifier("notif.markAllRead")
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if vm.isLoading && vm.allItems.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorPane(err)
        } else if vm.filteredItems.isEmpty && !Reachability.shared.isOnline && vm.allItems.isEmpty {
            OfflineEmptyStateView(entityName: "notifications")
        } else if vm.filteredItems.isEmpty {
            emptyState
        } else {
            groupedList
        }
    }

    // MARK: - Grouped list

    private var groupedList: some View {
        List {
            ForEach(vm.daySections) { section in
                Section {
                    ForEach(section.items) { note in
                        NotificationRowView(note: note)
                            .listRowBackground(Color.bizarreSurface1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // §13.1 Tap → deep link
                                if let path = deepLinkPath(for: note),
                                   let url = URL(string: "bizarrecrm://\(path)") {
                                    openURL(url)
                                }
                                if !note.read {
                                    Task { await vm.markRead(id: note.id) }
                                }
                            }
                            // Trailing: mark read
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !note.read {
                                    Button {
                                        Task { await vm.markRead(id: note.id) }
                                    } label: {
                                        Label("Mark read", systemImage: "envelope.open")
                                    }
                                    .tint(.bizarreTeal)
                                    .accessibilityIdentifier("notif.swipe.read.\(note.id)")
                                }
                            }
                            // Leading: dismiss (PATCH /dismiss)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await vm.dismiss(id: note.id) }
                                } label: {
                                    Label("Dismiss", systemImage: "xmark.circle")
                                }
                                .accessibilityIdentifier("notif.swipe.dismiss.\(note.id)")
                            }
                    }
                } header: {
                    dayHeader(section.header)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func dayHeader(_ label: String) -> some View {
        Text(label)
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandGlass(.regular, tint: .bizarreSurface2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Section: \(label)")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.bizarreSurface2)
                    .frame(width: 100, height: 100)
                Image(systemName: "bell.badge.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.xs) {
                Text(emptyStateTitle)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
                Text(emptyStateSubtitle)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(emptyStateTitle). \(emptyStateSubtitle)")
    }

    private var emptyStateTitle: String {
        switch vm.activeFilter {
        case .all:              return "All caught up"
        case .unread:           return "No unread notifications"
        case .byType(let t):    return "No \(t.displayName) notifications"
        }
    }

    private var emptyStateSubtitle: String {
        switch vm.activeFilter {
        case .all:              return "Nothing new. Check back later."
        case .unread:           return "You've read everything."
        case .byType:           return "None in this category yet."
        }
    }

    // MARK: - Error pane

    private func errorPane(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load notifications")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(err)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success banner overlay

    @ViewBuilder
    private var successBannerOverlay: some View {
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

    // MARK: - Deep-link resolver

    /// §13.1 Map a `NotificationItem` → `bizarrecrm://` path fragment.
    /// Only known entity types are resolved; unknown types return nil (security).
    private func deepLinkPath(for note: NotificationItem) -> String? {
        // Entity allowlist — prevent injected types (§13.2 security rule).
        let allowed: Set<String> = [
            "ticket", "invoice", "customer", "sms_thread",
            "appointment", "estimate", "lead"
        ]
        guard let rawType = note.entityType?.lowercased(),
              allowed.contains(rawType) else { return nil }
        guard let entityId = note.entityId else { return nil }

        switch rawType {
        case "ticket":          return "tickets/\(entityId)"
        case "invoice":         return "invoices/\(entityId)"
        case "customer":        return "customers/\(entityId)"
        case "sms_thread":      return "sms/\(entityId)"
        case "appointment":     return "appointments/\(entityId)"
        case "estimate":        return "estimates/\(entityId)"
        case "lead":            return "leads/\(entityId)"
        default:                return nil
        }
    }

    // MARK: - Chip icon helper

    private func chipIcon(_ chip: NotificationFilterChip) -> String {
        switch chip {
        case .all:              return "bell"
        case .unread:           return "envelope.badge"
        case .byType(let t):
            switch t {
            case .ticket:       return "wrench.and.screwdriver"
            case .sms:          return "message"
            case .invoice:      return "doc.text"
            case .payment:      return "creditcard"
            case .appointment:  return "calendar"
            case .mention:      return "at"
            case .system:       return "gearshape"
            }
        }
    }
}

// MARK: - NotificationRowView

/// Single notification list row — extracted for reuse and testing.
public struct NotificationRowView: View {
    public let note: NotificationItem

    public init(note: NotificationItem) { self.note = note }

    public var body: some View {
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
                    .lineLimit(2)

                if let msg = note.message, !msg.isEmpty {
                    Text(msg)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(3)
                }

                if let ts = note.createdAt {
                    Text(relativeTime(from: ts))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer(minLength: 0)

            if !note.read {
                Circle()
                    .fill(Color.bizarreMagenta)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(note.read ? [] : [.isSelected])
    }

    private var accessibilityLabel: String {
        let status = note.read ? "Read" : "Unread"
        let title = note.title ?? "Notification"
        let msg = note.message ?? ""
        let time = note.createdAt.map { relativeTime(from: $0) } ?? ""
        return "\(status). \(title). \(msg). \(time)"
    }

    private func iconForType(_ type: String?) -> String {
        let t = type?.lowercased() ?? ""
        if t.contains("ticket")    { return "wrench.and.screwdriver" }
        if t.contains("sms")       { return "message" }
        if t.contains("invoice")   { return "doc.text" }
        if t.contains("payment") || t.contains("refund") { return "creditcard" }
        if t.contains("appoint")   { return "calendar" }
        if t.contains("mention")   { return "at" }
        if t.contains("inventory") { return "shippingbox" }
        return "bell"
    }

    /// Relative time string. Same logic as the old `NotificationListView.Row`.
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
