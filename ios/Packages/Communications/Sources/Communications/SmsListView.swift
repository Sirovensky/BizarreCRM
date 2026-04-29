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
    /// §91.1 §5 — compose sheet for "+ New conversation" CTA on empty state.
    @State private var showCompose: Bool = false
    private let repo: SmsRepository
    private let threadRepo: SmsThreadRepository
    private let api: APIClient

    public init(repo: SmsRepository, threadRepo: SmsThreadRepository, api: APIClient) {
        self.repo = repo
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
            // §5 — compose sheet triggered by "+ New conversation" empty-state CTA (iPhone path).
            .sheet(isPresented: $showCompose) {
                SmsComposerInlineBar(api: api, repo: repo, onSend: { [self] phone, _ in
                    await MainActor.run {
                        showCompose = false
                        if !phone.isEmpty { path.append(phone) }
                    }
                })
            }
            .actionErrorBanner(isVisible: vm.actionError != nil, message: vm.actionError ?? "") {
                vm.clearActionError()
            }
        }
    }

    // MARK: - iPad layout (NavigationSplitView handled by parent; this adds keyboard shortcuts + hover)

    private var regularBody: some View {
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
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                }
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
            .sheet(isPresented: $showTemplates) {
                MessageTemplateListView(api: api)
            }
            // §5 — compose sheet triggered by "+ New conversation" empty-state CTA (iPad path).
            .sheet(isPresented: $showCompose) {
                SmsComposerInlineBar(api: api, repo: repo, onSend: { [self] phone, _ in
                    await MainActor.run {
                        showCompose = false
                        if !phone.isEmpty { path.append(phone) }
                    }
                })
            }
            .actionErrorBanner(isVisible: vm.actionError != nil, message: vm.actionError ?? "") {
                vm.clearActionError()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            SmsErrorStateView(
                message: err,
                technicalDetail: vm.rawErrorDetail,
                onRetry: { Task { await vm.load() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.conversations.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "conversations")
        } else if vm.conversations.isEmpty {
            SmsEmptyStateView(
                isSearch: !searchText.isEmpty,
                onNewConversation: { showCompose = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            conversationList
        }
    }

    private var conversationList: some View {
        List {
            ForEach(vm.conversations) { c in
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

// MARK: - SmsErrorStateView (§91.1)

/// Full-screen error state for the conversations list.
///
/// - Shows a friendly headline + user-readable message.
/// - Collapses the raw technical detail behind a "Show details" `DisclosureGroup`
///   so power-users and support staff can copy the error without it being the
///   first thing a regular user reads.
/// - "Try again" is a brand-prominent CTA button with a ≥44 pt tap target (§3).
/// - Shared across `SmsListView` (iPhone) and `SmsThreeColumnView` (iPad columns).
struct SmsErrorStateView: View {
    let message: String
    let technicalDetail: String?
    let onRetry: () -> Void

    @State private var showDetail: Bool = false

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)

            Text("Couldn't load conversations")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)

            // §91.1 — technical payload collapsed behind disclosure; never the lead.
            if let detail = technicalDetail, !detail.isEmpty {
                DisclosureGroup("Show details", isExpanded: $showDetail) {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .padding(.top, BrandSpacing.xxs)
                }
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.lg)
            }

            // §91.3 — brand-prominent CTA, minimum 44 pt height, correct VoiceOver label.
            Button(action: onRetry) {
                Text("Try again")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityLabel("Retry loading conversations")
        }
    }
}

// MARK: - SmsEmptyStateView (§91.5)

/// Empty state shown when there are no conversations (or no search results).
///
/// On a non-search empty state a prominent "+ New conversation" CTA is shown
/// so staff can immediately start a thread without hunting for the compose button.
struct SmsEmptyStateView: View {
    let isSearch: Bool
    let onNewConversation: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "message")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Text(isSearch ? "No results" : "No conversations yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if !isSearch {
                // §5 — CTA on empty landing; ≥44 pt, brand orange, clear VoiceOver label.
                Button(action: onNewConversation) {
                    Label("New conversation", systemImage: "square.and.pencil")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Start a new SMS conversation")
            }
        }
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
