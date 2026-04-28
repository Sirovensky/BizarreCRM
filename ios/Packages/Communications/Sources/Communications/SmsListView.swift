import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

public struct SmsListView: View {
    @State private var vm: SmsListViewModel
    @State private var searchText: String = ""
    @State private var path: [String] = []
    @State private var showTemplates: Bool = false
    @State private var showCompose: Bool = false      // §12.1 Compose FAB
    private let threadRepo: SmsThreadRepository
    private let api: APIClient

    public init(repo: SmsRepository, threadRepo: SmsThreadRepository, api: APIClient) {
        self.threadRepo = threadRepo
        self.api = api
        _vm = State(wrappedValue: SmsListViewModel(repo: repo))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactBody
            } else {
                regularBody
            }
        }
    }

    // MARK: - iPhone layout

    private var compactBody: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("SMS")
            .searchable(text: $searchText, prompt: "Search by name or phone")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .navigationDestination(for: String.self) { phone in
                SmsThreadView(repo: threadRepo, phoneNumber: phone)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showTemplates = true } label: {
                        Image(systemName: "text.bubble.badge.clock")
                    }
                    .accessibilityLabel("Message Templates")
                }
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
            .sheet(isPresented: $showTemplates) {
                MessageTemplateListView(api: api)
            }
            .actionErrorBanner(isVisible: vm.actionError != nil, message: vm.actionError ?? "") {
                vm.clearActionError()
            }
        }
    }

    // MARK: - iPad layout — permanent left sidebar with conversation list,
    // detail pane on right shows the selected thread or an empty-state.

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedPhone: String?

    private var regularBody: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar — wrap in `NavigationStack` so `.navigationTitle`,
            // `.toolbar`, and `.searchable` have a host to render into.
            NavigationStack {
                ZStack {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    content
                }
                .navigationTitle("SMS")
                .searchable(text: $searchText, prompt: "Search by name or phone")
                .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
                .task { await vm.load() }
                .refreshable { await vm.refresh() }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showTemplates = true } label: {
                            Image(systemName: "text.bubble.badge.clock")
                        }
                        .accessibilityLabel("Message Templates")
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                    }
                    ToolbarItem(placement: .automatic) {
                        StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                    }
                }
                .sheet(isPresented: $showTemplates) {
                    MessageTemplateListView(api: api)
                }
                .actionErrorBanner(isVisible: vm.actionError != nil, message: vm.actionError ?? "") {
                    vm.clearActionError()
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 480)
        } detail: {
            if let phone = selectedPhone {
                NavigationStack {
                    SmsThreadView(repo: threadRepo, phoneNumber: phone)
                }
            } else {
                ZStack {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    VStack(spacing: BrandSpacing.md) {
                        Image(systemName: "message")
                            .font(.system(size: 48))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text("Select a conversation")
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("Pick a thread on the left or start a new one.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: path) { _, new in
            // The conversation rows still push to `path` (used by the iPhone
            // `NavigationStack`). On iPad we mirror the most recent pushed
            // phone into `selectedPhone` so the detail column updates.
            // `NavigationLink(value:)` taps inside the sidebar `NavigationStack`
            // append to `path`, which fires this observer.
            selectedPhone = new.last
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load conversations")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.conversations.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "conversations")
        } else if vm.filteredConversations.isEmpty {
            emptyFilteredState
        } else {
            conversationListWithChips
        }
    }

    // MARK: - Empty filtered state — §12.13

    private var emptyFilteredState: some View {
        VStack(spacing: BrandSpacing.md) {
            SmsFilterChipsView(selected: $vm.filter.tab, counts: vm.tabCounts)
            Spacer()
            Image(systemName: vm.filter.isDefault ? "message" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            if vm.filter.isDefault && searchText.isEmpty {
                // §12.13 "No threads" empty state — CTA to compose new
                Text("No conversations yet")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text("Start a conversation with a customer.")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button {
                    showCompose = true
                } label: {
                    Label("Start a Conversation", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Start a new conversation")
                .sheet(isPresented: $showCompose) {
                    ComposeNewThreadView(api: api) { phone in
                        path.append(phone)
                    }
                }
            } else {
                Text(searchText.isEmpty
                     ? "No \(vm.filter.tab.label.lowercased()) conversations"
                     : "No results for \"\(searchText)\"")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                if !vm.filter.isDefault {
                    Button("Show all") {
                        withAnimation { vm.filter.tab = .all }
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)
                }
            }
            Spacer()
        }
    }

    // MARK: - List with filter chips + FAB

    private var conversationListWithChips: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                SmsFilterChipsView(selected: $vm.filter.tab, counts: vm.tabCounts)
                conversationList
            }
            // §12.1 Compose new (FAB)
            composeFAB
        }
    }

    // MARK: - Compose FAB (§12.1)

    private var composeFAB: some View {
        Button {
            showCompose = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(BrandSpacing.md)
                .background(Color.bizarreOrange, in: Circle())
                .shadow(radius: 4, y: 2)
        }
        .padding(BrandSpacing.lg)
        .accessibilityLabel("Compose new message")
        .keyboardShortcut("n", modifiers: [.command])
        .sheet(isPresented: $showCompose) {
            ComposeNewThreadView(api: api) { phone in
                path.append(phone)
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(vm.filteredConversations) { c in
                NavigationLink(value: c.convPhone) {
                    ConversationRow(conversation: c)
                }
                .listRowBackground(Color.bizarreSurface1)
                // Leading swipe: mark read / unread
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if c.unreadCount > 0 {
                        Button {
                            Task { await vm.markRead(phone: c.convPhone) }
                        } label: {
                            Label("Mark Read", systemImage: "envelope.open")
                        }
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Mark conversation with \(c.displayName) as read")
                    }
                }
                // Trailing swipe: flag / pin / archive
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        Task { await vm.toggleFlag(phone: c.convPhone) }
                    } label: {
                        Label(c.isFlagged ? "Unflag" : "Flag",
                              systemImage: c.isFlagged ? "flag.slash" : "flag")
                    }
                    .tint(c.isFlagged ? .bizarreOnSurfaceMuted : .bizarreError)
                    .accessibilityLabel(c.isFlagged ? "Unflag conversation with \(c.displayName)" : "Flag conversation with \(c.displayName)")

                    Button {
                        Task { await vm.togglePin(phone: c.convPhone) }
                    } label: {
                        Label(c.isPinned ? "Unpin" : "Pin",
                              systemImage: c.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(.bizarreOrange)
                    .accessibilityLabel(c.isPinned ? "Unpin conversation with \(c.displayName)" : "Pin conversation with \(c.displayName)")

                    Button {
                        Task { await vm.toggleArchive(phone: c.convPhone) }
                    } label: {
                        Label(c.isArchived ? "Unarchive" : "Archive",
                              systemImage: c.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    .tint(.bizarreMagenta)
                    .accessibilityLabel(c.isArchived ? "Unarchive conversation with \(c.displayName)" : "Archive conversation with \(c.displayName)")
                }
                // Context menu (iPad hover + long-press)
                .contextMenu {
                    if c.unreadCount > 0 {
                        Button {
                            Task { await vm.markRead(phone: c.convPhone) }
                        } label: {
                            Label("Mark Read", systemImage: "envelope.open")
                        }
                    }
                    Button {
                        Task { await vm.toggleFlag(phone: c.convPhone) }
                    } label: {
                        Label(c.isFlagged ? "Remove Flag" : "Flag",
                              systemImage: c.isFlagged ? "flag.slash" : "flag")
                    }
                    Button {
                        Task { await vm.togglePin(phone: c.convPhone) }
                    } label: {
                        Label(c.isPinned ? "Unpin" : "Pin to Top",
                              systemImage: c.isPinned ? "pin.slash" : "pin")
                    }
                    Button {
                        Task { await vm.toggleArchive(phone: c.convPhone) }
                    } label: {
                        Label(c.isArchived ? "Unarchive" : "Archive",
                              systemImage: c.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    Divider()
                    Button {
                        path.append(c.convPhone)
                    } label: {
                        Label("Open", systemImage: "arrow.right")
                    }
                }
                #if !os(macOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - ConversationRow

private struct ConversationRow: View {
    let conversation: SmsConversation

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            ZStack {
                Circle()
                    .fill(conversation.unreadCount > 0 ? Color.bizarreOrange : Color.bizarreOrangeContainer)
                Text(conversation.avatarInitial)
                    .font(.brandTitleMedium())
                    .foregroundStyle(conversation.unreadCount > 0 ? Color.black : Color.bizarreOnOrange)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack(spacing: BrandSpacing.xs) {
                    Text(conversation.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .fontWeight(conversation.unreadCount > 0 ? .semibold : .regular)
                        .lineLimit(1)
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                    }
                    if conversation.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(.bizarreError)
                            .accessibilityHidden(true)
                    }
                    if conversation.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption)
                            .foregroundStyle(.bizarreMagenta)
                            .accessibilityHidden(true)
                    }
                }
                if let msg = conversation.lastMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.brandBodyMedium())
                        .foregroundStyle(conversation.unreadCount > 0 ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                if let ts = conversation.lastMessageAt?.prefix(10) {
                    Text(String(ts))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
                if conversation.unreadCount > 0 {
                    Circle()
                        .fill(Color.bizarreMagenta)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.a11y(for: conversation))
    }

    static func a11y(for c: SmsConversation) -> String {
        var parts: [String] = [c.displayName]
        if c.isPinned { parts.append("Pinned") }
        if c.isFlagged { parts.append("Flagged") }
        if c.isArchived { parts.append("Archived") }
        if let msg = c.lastMessage, !msg.isEmpty { parts.append(msg) }
        if let ts = c.lastMessageAt?.prefix(10), !ts.isEmpty { parts.append(String(ts)) }
        if c.unreadCount > 0 { parts.append("\(c.unreadCount) unread") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - ActionErrorBanner modifier

private struct ActionErrorBannerModifier: ViewModifier {
    let isVisible: Bool
    let message: String
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isVisible {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Dismiss error")
                }
                .padding(BrandSpacing.md)
                .background(Color.bizarreError, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, BrandSpacing.md)
                .padding(.top, BrandSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: isVisible)
            }
        }
    }
}

private extension View {
    func actionErrorBanner(isVisible: Bool, message: String, onDismiss: @escaping () -> Void) -> some View {
        modifier(ActionErrorBannerModifier(isVisible: isVisible, message: message, onDismiss: onDismiss))
    }
}
