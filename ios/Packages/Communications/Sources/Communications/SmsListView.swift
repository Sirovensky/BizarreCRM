import SwiftUI
import Core
import DesignSystem
import Networking

public struct SmsListView: View {
    @State private var vm: SmsListViewModel
    @State private var searchText: String = ""
    @State private var path: [String] = []
    private let threadRepo: SmsThreadRepository

    public init(repo: SmsRepository, threadRepo: SmsThreadRepository) {
        self.threadRepo = threadRepo
        _vm = State(wrappedValue: SmsListViewModel(repo: repo))
    }

    public var body: some View {
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
        }
    }

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
        } else if vm.conversations.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "message")
                    .font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(searchText.isEmpty ? "No conversations yet" : "No results")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.conversations) { c in
                    NavigationLink(value: c.convPhone) {
                        ConversationRow(conversation: c)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

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
        if let msg = c.lastMessage, !msg.isEmpty { parts.append(msg) }
        if let ts = c.lastMessageAt?.prefix(10), !ts.isEmpty { parts.append(String(ts)) }
        if c.unreadCount > 0 { parts.append("\(c.unreadCount) unread") }
        return parts.joined(separator: ". ")
    }
}
