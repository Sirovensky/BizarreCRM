import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - TeamInboxView
//
// §12.1 — Team inbox tab. Shared inbox for tenant staff.
// Shows all non-archived conversations with an "Assign" action per row.
//
// Server: POST /inbox/:id/assign (body: { assignee_id }).
// Assign feature is an overlay until server confirms the field is live.
//
// iPhone: List with assign swipe action.
// iPad: 2-col split (conversations | thread).

public struct TeamInboxView: View {

    @State private var vm: TeamInboxViewModel
    @State private var selectedPhone: String?
    private let threadRepo: SmsThreadRepository

    public init(api: APIClient, threadRepo: SmsThreadRepository) {
        self.threadRepo = threadRepo
        _vm = State(wrappedValue: TeamInboxViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .task { await vm.load() }
    }

    // MARK: - iPhone

    private var iPhoneLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                listContent
            }
            .navigationTitle("Team Inbox")
            .refreshable { await vm.load() }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
        }
    }

    // MARK: - iPad

    private var iPadLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                listContent
            }
            .navigationTitle("Team Inbox")
            .frame(minWidth: 280, idealWidth: 340)
            .refreshable { await vm.load() }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
        } detail: {
            if let phone = selectedPhone {
                SmsThreadView(repo: threadRepo, phoneNumber: phone)
            } else {
                ContentUnavailableView(
                    "Select a Conversation",
                    systemImage: "tray",
                    description: Text("Choose a conversation from the inbox")
                )
            }
        }
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load team inbox").font(.brandTitleMedium())
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.conversations.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "tray").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Team inbox is empty").font(.brandTitleMedium())
                Text("No conversations waiting for assignment.").font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(vm.conversations) { conv in
                if Platform.isCompact {
                    NavigationLink(value: conv.convPhone) {
                        TeamInboxRow(conv: conv)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            Task { await vm.assignToMe(phone: conv.convPhone) }
                        } label: {
                            Label("Assign to me", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .tint(.bizarreOrange)
                    }
                } else {
                    TeamInboxRow(conv: conv)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedPhone = conv.convPhone }
                        .listRowBackground(
                            selectedPhone == conv.convPhone
                                ? Color.bizarreOrangeContainer.opacity(0.3)
                                : Color.bizarreSurface1
                        )
                        .hoverEffect(.highlight)
                        .contextMenu {
                            Button {
                                Task { await vm.assignToMe(phone: conv.convPhone) }
                            } label: {
                                Label("Assign to me", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - TeamInboxRow

private struct TeamInboxRow: View {
    let conv: SmsConversation

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle().fill(Color.bizarreOrangeContainer)
                Text(conv.avatarInitial)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnOrange)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(conv.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let last = conv.lastMessage {
                    Text(last)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if conv.unreadCount > 0 {
                Text("\(conv.unreadCount)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreOrange, in: Capsule())
                    .accessibilityLabel("\(conv.unreadCount) unread")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conv.displayName). \(conv.unreadCount > 0 ? "\(conv.unreadCount) unread." : "")")
    }
}

// MARK: - TeamInboxViewModel

@MainActor
@Observable
public final class TeamInboxViewModel {
    public private(set) var conversations: [SmsConversation] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = conversations.isEmpty
        defer { isLoading = false }
        errorMessage = nil
        do {
            conversations = try await api.listSmsConversations(keyword: nil, includeArchived: false)
            lastSyncedAt = Date()
        } catch {
            AppLog.ui.error("TeamInbox load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Assign the conversation to the current user (self-assign).
    /// Server route: POST /inbox/:id/assign  body: { assignee_id: currentUserId }.
    /// Optimistic UI: no local change (server does not yet return assignee in list response).
    public func assignToMe(phone: String) async {
        do {
            try await api.assignInboxConversation(phone: phone)
        } catch {
            AppLog.ui.error("Assign failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
