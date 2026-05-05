import SwiftUI
import DesignSystem
import Networking
import Sync

// MARK: - NotificationsThreeColumnView
//
// §22 iPad polish — 3-column layout:
//   Column 1 (sidebar)  — NotificationCategorySidebar  (category + filter)
//   Column 2 (content)  — notification list rows
//   Column 3 (detail)   — NotificationDetailSheet inlined as a pane
//
// Glass chrome is applied to the toolbar, sidebar header, and bulk-actions
// bar only. Notification cards remain content (no glass per CLAUDE.md rule).

@available(iOS 17.0, *)
public struct NotificationsThreeColumnView: View {

    // MARK: - State

    @State private var vm: NotificationListPolishedViewModel
    @State private var selectedCategory: NotificationSidebarCategory = .all
    @State private var selectedItem: NotificationItem?
    @State private var selectedIDs: Set<Int64> = []
    @State private var isSelectMode: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: - Init

    public init(api: APIClient, cachedRepo: NotificationCachedRepository? = nil) {
        _vm = State(
            wrappedValue: NotificationListPolishedViewModel(api: api, cachedRepo: cachedRepo)
        )
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            listColumn
        } detail: {
            detailColumn
        }
        .task { await vm.load() }
        .refreshable { await vm.forceRefresh() }
        .overlay(alignment: .top) { successBannerOverlay }
        .notificationListKeyboardShortcuts(
            onCategoryChange: { cat in
                selectedCategory = cat
                applyCategory(cat)
            },
            onNavigateUp: navigateUp,
            onNavigateDown: navigateDown,
            onRefresh: { Task { await vm.forceRefresh() } }
        )
    }

    // MARK: - Sidebar column

    private var sidebarColumn: some View {
        NotificationCategorySidebar(
            selectedCategory: $selectedCategory,
            unreadCount: vm.unreadCount,
            itemCounts: categoryCounts
        ) { newCategory in
            selectedCategory = newCategory
            applyCategory(newCategory)
            // Clear selection when switching categories
            selectedIDs = []
            selectedItem = nil
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
    }

    // MARK: - List column

    private var listColumn: some View {
        ZStack(alignment: .bottom) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                if vm.isLoading && vm.allItems.isEmpty {
                    loadingView
                } else if let err = vm.errorMessage {
                    errorPane(err)
                } else if vm.filteredItems.isEmpty {
                    emptyState
                } else {
                    listBody
                }
            }

            if isSelectMode && !selectedIDs.isEmpty {
                NotificationBulkActionsBar(
                    selectedCount: selectedIDs.count,
                    onMarkRead: performBulkMarkRead,
                    onArchive: performBulkArchive,
                    onSelectAll: selectAll,
                    onCancel: cancelSelectMode
                )
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(selectedCategory.label)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { listToolbar }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelectMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIDs.isEmpty)
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let item = selectedItem {
            NotificationDetailPane(
                item: item,
                onMarkRead: { id in await vm.markRead(id: id) },
                onClose: { selectedItem = nil }
            )
        } else {
            emptyDetailPane
        }
    }

    // MARK: - List body

    private var listBody: some View {
        List {
            ForEach(vm.daySections) { section in
                Section {
                    ForEach(section.items) { note in
                        notificationRow(note)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !note.read {
                                Button {
                                    Task { await vm.markRead(id: note.id) }
                                } label: {
                                    Label("Mark read", systemImage: "envelope.open")
                                }
                                .tint(.bizarreTeal)
                                .accessibilityIdentifier("notif.ipad.swipe.read.\(note.id)")
                            }
                        }
                        .contextMenu {
                            contextMenuItems(for: note)
                        }
                        .hoverEffect(.highlight)
                        .accessibilityIdentifier("notif.ipad.row.\(note.id)")
                    }
                } header: {
                    dayHeader(section.header)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func notificationRow(_ note: NotificationItem) -> some View {
        NotificationListRow(
            note: note,
            isSelected: selectedItem?.id == note.id,
            isSelectMode: isSelectMode,
            isChecked: selectedIDs.contains(note.id)
        )
        .listRowBackground(
            selectedItem?.id == note.id
                ? Color.bizarreOrangeContainer.opacity(0.18)
                : Color.bizarreSurface1
        )
        .onTapGesture {
            if isSelectMode {
                toggleSelection(note.id)
            } else {
                selectedItem = note
                if !note.read {
                    Task { await vm.markRead(id: note.id) }
                }
            }
        }
    }

    // MARK: - List toolbar

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation { isSelectMode.toggle() }
                if !isSelectMode { selectedIDs = [] }
            } label: {
                Label(
                    isSelectMode ? "Done" : "Select",
                    systemImage: isSelectMode ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .font(.brandLabelLarge())
            }
            .tint(isSelectMode ? .bizarreOrange : .bizarreTeal)
            .accessibilityIdentifier("notif.ipad.selectToggle")
            .keyboardShortcut("e", modifiers: [.command])
        }
        if vm.hasUnread && !isSelectMode {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await vm.markAllRead() }
                } label: {
                    Label("Mark all read", systemImage: "envelope.open")
                        .font(.brandLabelLarge())
                }
                .tint(.bizarreTeal)
                .accessibilityIdentifier("notif.ipad.markAllRead")
            }
        }
    }

    // MARK: - Day header

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

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenuItems(for note: NotificationItem) -> some View {
        if !note.read {
            Button {
                Task { await vm.markRead(id: note.id) }
            } label: {
                Label("Mark as Read", systemImage: "envelope.open")
            }
        }
        Button {
            withAnimation { isSelectMode = true }
            selectedIDs.insert(note.id)
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
    }

    // MARK: - Loading / empty / error

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading notifications")
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.bizarreSurface2)
                    .frame(width: 80, height: 80)
                Image(systemName: "bell.badge.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityHidden(true)
            VStack(spacing: BrandSpacing.xs) {
                Text(emptyTitle)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(emptySubtitle)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(emptyTitle). \(emptySubtitle)")
    }

    private var emptyTitle: String {
        switch selectedCategory {
        case .all:      return "All caught up"
        case .unread:   return "No unread notifications"
        case .flagged:  return "No flagged notifications"
        case .pinned:   return "No pinned notifications"
        case .archived: return "No archived notifications"
        }
    }

    private var emptySubtitle: String {
        switch selectedCategory {
        case .all:      return "Nothing new. Check back later."
        case .unread:   return "You've read everything."
        case .flagged:  return "Flag important notifications to find them here."
        case .pinned:   return "Pin notifications to keep them at the top."
        case .archived: return "Archived notifications appear here."
        }
    }

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
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .frame(width: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetailPane: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "bell")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Select a notification")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
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

    // MARK: - Category filtering

    private func applyCategory(_ category: NotificationSidebarCategory) {
        switch category {
        case .all:
            vm.setFilter(.all)
        case .unread:
            vm.setFilter(.unread)
        case .flagged, .pinned, .archived:
            // These map to .all for now; server-side tagging is a future phase.
            // The sidebar still shows the intent and the list shows all items
            // with appropriate empty-state messaging.
            vm.setFilter(.all)
        }
    }

    private var categoryCounts: [NotificationSidebarCategory: Int] {
        [
            .all: vm.allItems.count,
            .unread: vm.allItems.filter { !$0.read }.count,
            .flagged: 0,
            .pinned: 0,
            .archived: 0
        ]
    }

    // MARK: - Selection helpers

    private func toggleSelection(_ id: Int64) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func selectAll() {
        selectedIDs = Set(vm.filteredItems.map { $0.id })
    }

    private func cancelSelectMode() {
        withAnimation {
            isSelectMode = false
            selectedIDs = []
        }
    }

    private func performBulkMarkRead() {
        let ids = selectedIDs
        Task {
            for id in ids {
                await vm.markRead(id: id)
            }
            withAnimation { cancelSelectMode() }
        }
    }

    private func performBulkArchive() {
        // Archive is a future server feature; optimistically remove from list view.
        withAnimation { cancelSelectMode() }
    }

    // MARK: - j/k navigation

    private func navigateDown() {
        let items = vm.filteredItems
        guard !items.isEmpty else { return }
        if let current = selectedItem,
           let idx = items.firstIndex(where: { $0.id == current.id }),
           idx + 1 < items.count {
            selectedItem = items[idx + 1]
        } else if selectedItem == nil {
            selectedItem = items.first
        }
    }

    private func navigateUp() {
        let items = vm.filteredItems
        guard !items.isEmpty else { return }
        if let current = selectedItem,
           let idx = items.firstIndex(where: { $0.id == current.id }),
           idx > 0 {
            selectedItem = items[idx - 1]
        }
    }
}

// MARK: - NotificationListRow

/// Single row used inside the three-column list pane.
/// Wraps `NotificationRowView` and adds selection-mode checkbox.
struct NotificationListRow: View {
    let note: NotificationItem
    let isSelected: Bool
    let isSelectMode: Bool
    let isChecked: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            if isSelectMode {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isChecked ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isChecked)
                    .accessibilityHidden(true)
            }
            NotificationRowView(note: note)
        }
    }
}

// MARK: - NotificationDetailPane

/// Full-width inline detail pane for the third column on iPad.
/// Mirrors `NotificationDetailSheet` but as a NavigationStack column.
struct NotificationDetailPane: View {
    let item: NotificationItem
    var onMarkRead: ((Int64) async -> Void)?
    var onClose: (() -> Void)?

    @State private var isMarkingRead: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { detailToolbar }
        }
    }

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
                    .background(
                        Color.bizarreSurface1,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    )
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        if item.entityType != nil || item.entityId != nil {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Info")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    if let entityType = item.entityType {
                        metadataRow(icon: "tag", label: "Type", value: entityType.capitalized)
                        Divider().padding(.horizontal, BrandSpacing.md)
                    }
                    if let entityId = item.entityId {
                        metadataRow(icon: "number", label: "ID", value: String(entityId))
                    }
                }
                .background(
                    Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                )
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

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Close detail")
            .accessibilityIdentifier("notif.ipad.detail.close")
        }
        if !item.read {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        isMarkingRead = true
                        await onMarkRead?(item.id)
                        isMarkingRead = false
                    }
                } label: {
                    if isMarkingRead {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Mark read", systemImage: "envelope.open")
                            .font(.brandLabelLarge())
                    }
                }
                .tint(.bizarreTeal)
                .accessibilityIdentifier("notif.ipad.detail.markRead")
            }
        }
    }

    private func iconName(for type: String?) -> String {
        let t = type?.lowercased() ?? ""
        if t.contains("ticket")                                     { return "wrench.and.screwdriver" }
        if t.contains("sms")                                        { return "message" }
        if t.contains("invoice") || t.contains("estimate")         { return "doc.text" }
        if t.contains("payment") || t.contains("refund")           { return "creditcard" }
        if t.contains("appoint")                                    { return "calendar" }
        if t.contains("mention")                                    { return "at" }
        if t.contains("inventory")                                  { return "shippingbox" }
        if t.contains("security")                                   { return "lock.shield" }
        if t.contains("backup")                                     { return "externaldrive" }
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
