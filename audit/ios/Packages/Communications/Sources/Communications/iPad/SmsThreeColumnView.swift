import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

// MARK: - SmsFolder

/// Top-level filter applied to the thread list column.
public enum SmsFolder: String, CaseIterable, Identifiable, Sendable {
    case all       = "All"
    case flagged   = "Flagged"
    case pinned    = "Pinned"
    case archived  = "Archived"

    public var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all:      return "message"
        case .flagged:  return "flag"
        case .pinned:   return "pin"
        case .archived: return "archivebox"
        }
    }

    /// Predicate that matches the folder against a conversation.
    func matches(_ conv: SmsConversation) -> Bool {
        switch self {
        case .all:      return !conv.isArchived
        case .flagged:  return conv.isFlagged && !conv.isArchived
        case .pinned:   return conv.isPinned  && !conv.isArchived
        case .archived: return conv.isArchived
        }
    }
}

// MARK: - SmsThreeColumnView

/// iPad-only three-column NavigationSplitView:
///   Column 1 (sidebar)  — folder filter (All / Flagged / Pinned / Archived)
///   Column 2 (content)  — thread list filtered by selected folder
///   Column 3 (detail)   — conversation (SmsThreadView)
///
/// Liquid Glass on toolbar chrome only; never on list rows or bubbles.
/// Gate: only instantiated when `Platform.isCompact == false`.
public struct SmsThreeColumnView: View {
    // MARK: Dependencies
    private let repo: SmsRepository
    private let threadRepo: SmsThreadRepository
    private let api: APIClient

    // MARK: Column selection state
    @State private var selectedFolder: SmsFolder = .all
    @State private var selectedPhone: String?

    // MARK: List + search
    @State private var vm: SmsListViewModel
    @State private var searchText: String = ""

    // MARK: Compose sheet
    @State private var showCompose: Bool = false

    // MARK: Recent-tickets callback
    /// Called when the user taps a ticket in the "Recent Tickets" section.
    /// The app-shell resolves navigation; the Communications module stays decoupled.
    public var onOpenTicket: ((Int64) -> Void)?

    public init(
        repo: SmsRepository,
        threadRepo: SmsThreadRepository,
        api: APIClient,
        onOpenTicket: ((Int64) -> Void)? = nil
    ) {
        self.repo = repo
        self.threadRepo = threadRepo
        self.api = api
        self.onOpenTicket = onOpenTicket
        _vm = State(wrappedValue: SmsListViewModel(repo: repo))
    }

    public var body: some View {
        NavigationSplitView {
            folderSidebar
        } content: {
            threadListColumn
        } detail: {
            detailColumn
        }
        .task { await vm.load() }
        .sheet(isPresented: $showCompose) {
            SmsComposerInlineBar(
                api: api,
                repo: repo,
                onSend: { phone, body in
                    _ = phone   // passed through to composer
                    _ = body
                }
            )
        }
    }

    // MARK: - Column 1: Folder Icon Rail (~72 pt wide)

    private var folderSidebar: some View {
        SmsIconRail(
            selectedFolder: $selectedFolder,
            folderCount: folderCount,
            onCompose: { showCompose = true }
        )
    }

    // MARK: - Column 2: Thread List

    private var threadListColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            threadListContent
        }
        .navigationTitle(selectedFolder.rawValue)
        .searchable(text: $searchText, prompt: "Search conversations")
        .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
        .refreshable { await vm.refresh() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
            }
        }
        .actionErrorBanner(isVisible: vm.actionError != nil, message: vm.actionError ?? "") {
            vm.clearActionError()
        }
    }

    @ViewBuilder
    private var threadListContent: some View {
        if vm.isLoading && vm.conversations.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.conversations.isEmpty {
            errorView(message: err)
        } else {
            let filtered = filteredConversations
            if filtered.isEmpty {
                emptyView
            } else {
                threadList(conversations: filtered)
            }
        }
    }

    // §91.1 §91.3 — delegate to shared SmsErrorStateView for consistent friendly error UI.
    private func errorView(message: String) -> some View {
        SmsErrorStateView(
            message: message,
            technicalDetail: vm.rawErrorDetail,
            onRetry: { Task { await vm.load() } }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: selectedFolder.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(searchText.isEmpty ? "No \(selectedFolder.rawValue.lowercased()) conversations" : "No results")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func threadList(conversations: [SmsConversation]) -> some View {
        List(conversations, selection: $selectedPhone) { conv in
            SmsThreadRow(conversation: conv, vm: vm)
                .tag(conv.convPhone)
                .listRowBackground(
                    conv.convPhone == selectedPhone
                        ? Color.bizarreOrange.opacity(0.10)
                        : Color.bizarreSurface1
                )
                .contextMenu {
                    SmsContextMenu(conversation: conv, vm: vm)
                }
                #if !os(macOS)
                .hoverEffect(.highlight)
                #endif
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Column 3: Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let phone = selectedPhone {
            let conversation = vm.conversations.first(where: { $0.convPhone == phone })
            VStack(spacing: 0) {
                // Recent tickets section — shown above the thread, below nav bar
                if let conv = conversation, let customerId = conv.customer?.id {
                    RecentTicketsSection(
                        api: api,
                        customerId: customerId,
                        onOpenTicket: onOpenTicket
                    )
                }
                SmsThreadView(repo: threadRepo, phoneNumber: phone)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        SmsComposerInlineBar(
                            api: api,
                            repo: repo,
                            targetPhone: phone,
                            onSend: { sentPhone, _ in
                                // Reload thread list after send so unread counts update.
                                Task { await vm.load() }
                                selectedPhone = sentPhone
                            }
                        )
                    }
            }
        } else {
            // §91.5 — right-pane empty state: show brand CTA to start a new conversation.
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "message.badge.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Select a conversation")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Button(action: { showCompose = true }) {
                    Label("New conversation", systemImage: "square.and.pencil")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Start a new SMS conversation")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bizarreSurfaceBase)
        }
    }

    // MARK: - Helpers

    private var filteredConversations: [SmsConversation] {
        vm.conversations.filter { selectedFolder.matches($0) }
    }

    private func folderCount(_ folder: SmsFolder) -> Int {
        vm.conversations.filter { folder.matches($0) }.count
    }
}

// MARK: - SmsThreadRow

/// Single thread list row — used in the content column.
struct SmsThreadRow: View {
    let conversation: SmsConversation
    let vm: SmsListViewModel

    // MARK: Compact row layout (iPad polish §1)
    // Heights: avatar 34 pt, vertical padding 4 pt, name 13 pt, preview 12 pt.

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.sm) {
            avatarView
            infoStack
            Spacer(minLength: 0)
            metaStack
        }
        .padding(.vertical, SmsThreadRow.verticalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    /// Exposed for test assertions.
    static let verticalPadding: CGFloat = 4
    /// Exposed for test assertions.
    static let avatarSize: CGFloat = 34
    /// Exposed for test assertions.
    static let nameFontSize: CGFloat = 13
    /// Exposed for test assertions.
    static let previewFontSize: CGFloat = 12

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(conversation.unreadCount > 0 ? Color.bizarreOrange : Color.bizarreOrangeContainer)
            Text(conversation.avatarInitial)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(conversation.unreadCount > 0 ? Color.black : Color.bizarreOnOrange)
        }
        .frame(width: SmsThreadRow.avatarSize, height: SmsThreadRow.avatarSize)
        .accessibilityHidden(true)
    }

    private var infoStack: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: BrandSpacing.xxs) {
                Text(conversation.displayName)
                    .font(.system(size: SmsThreadRow.nameFontSize, weight: conversation.unreadCount > 0 ? .semibold : .regular))
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                decoratorIcons
            }
            if let msg = conversation.lastMessage, !msg.isEmpty {
                Text(msg)
                    .font(.system(size: SmsThreadRow.previewFontSize))
                    .foregroundStyle(
                        conversation.unreadCount > 0 ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted
                    )
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var decoratorIcons: some View {
        if conversation.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
        }
        if conversation.isFlagged {
            Image(systemName: "flag.fill")
                .font(.system(size: 9))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
        }
    }

    private var metaStack: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let ts = conversation.lastMessageAt?.prefix(10) {
                Text(String(ts))
                    .font(.system(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            if conversation.unreadCount > 0 {
                Circle()
                    .fill(Color.bizarreMagenta)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
    }

    private var a11yLabel: String {
        var parts: [String] = [conversation.displayName]
        if conversation.isPinned  { parts.append("Pinned") }
        if conversation.isFlagged { parts.append("Flagged") }
        if let msg = conversation.lastMessage, !msg.isEmpty { parts.append(msg) }
        if let ts  = conversation.lastMessageAt?.prefix(10), !ts.isEmpty { parts.append(String(ts)) }
        if conversation.unreadCount > 0 { parts.append("\(conversation.unreadCount) unread") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - ActionErrorBanner modifier (local copy for column isolation)

private struct SmsThreeColErrorBannerModifier: ViewModifier {
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
                    Button(action: onDismiss) {
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
        modifier(SmsThreeColErrorBannerModifier(isVisible: isVisible, message: message, onDismiss: onDismiss))
    }
}
