import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - StarredMessage

public struct StarredMessage: Identifiable, Sendable, Hashable {
    public let id: Int64
    public let messageId: Int64
    public let threadPhone: String
    public let body: String
    public let createdAt: String?
    public let customerName: String?

    public init(
        messageId: Int64,
        threadPhone: String,
        body: String,
        createdAt: String?,
        customerName: String?
    ) {
        self.id = messageId
        self.messageId = messageId
        self.threadPhone = threadPhone
        self.body = body
        self.createdAt = createdAt
        self.customerName = customerName
    }
}

// MARK: - StarredMessagesResponse

public struct StarredMessagesResponse: Decodable, Sendable {
    public let messages: [StarredMessageDTO]
}

public struct StarredMessageDTO: Decodable, Sendable {
    public let id: Int64
    public let message: String?
    public let convPhone: String
    public let createdAt: String?
    public let customerName: String?

    enum CodingKeys: String, CodingKey {
        case id, message
        case convPhone = "conv_phone"
        case createdAt = "created_at"
        case customerName = "customer_name"
    }

    public var asDomain: StarredMessage {
        StarredMessage(
            messageId: id,
            threadPhone: convPhone,
            body: message ?? "",
            createdAt: createdAt,
            customerName: customerName
        )
    }
}

// MARK: - APIClient extension

public extension APIClient {
    func listStarredMessages() async throws -> [StarredMessage] {
        let resp = try await get("/api/v1/sms/messages/starred", as: StarredMessagesResponse.self)
        return resp.messages.map { $0.asDomain }
    }

    func unstarMessage(messageId: Int64) async throws {
        try await delete("/api/v1/sms/messages/\(messageId)/star")
    }

    func postStarMessage(messageId: Int64) async throws {
        _ = try await post("/api/v1/sms/messages/\(messageId)/star", body: StarPayload(), as: EmptyStarAck.self)
    }
}

private struct StarPayload: Encodable, Sendable { init() {} }
private struct EmptyStarAck: Decodable, Sendable {}

// MARK: - PinnedMessagesViewModel

@MainActor
@Observable
public final class PinnedMessagesViewModel: Sendable {
    public private(set) var messages: [StarredMessage] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            messages = try await api.listStarredMessages()
        } catch {
            AppLog.ui.error("Starred messages load: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func unstar(_ msg: StarredMessage) async {
        messages.removeAll { $0.id == msg.id }
        do {
            try await api.unstarMessage(messageId: msg.messageId)
        } catch {
            AppLog.ui.error("Unstar failed: \(error.localizedDescription, privacy: .public)")
            await load() // revert
        }
    }
}

// MARK: - MessagePinnedCollectionView

/// "Starred" tab showing all starred messages across threads.
/// iPhone: plain list. iPad: two-column grid.
public struct MessagePinnedCollectionView: View {
    @State private var vm: PinnedMessagesViewModel

    /// Navigation callback to open a thread from the starred view.
    public var onOpenThread: ((String) -> Void)?

    public init(api: APIClient, onOpenThread: ((String) -> Void)? = nil) {
        _vm = State(wrappedValue: PinnedMessagesViewModel(api: api))
        self.onOpenThread = onOpenThread
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Starred Messages")
            .refreshable { await vm.load() }
        }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .refreshable { await vm.load() }
    }

    // MARK: - Shared content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorView(err)
        } else if vm.messages.isEmpty {
            emptyView
        } else if Platform.isCompact {
            starredList
        } else {
            starredGrid
        }
    }

    // MARK: - List (iPhone)

    private var starredList: some View {
        List {
            ForEach(vm.messages) { msg in
                StarredRow(message: msg) {
                    onOpenThread?(msg.threadPhone)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await vm.unstar(msg) }
                    } label: {
                        Label("Unstar", systemImage: "star.slash")
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Grid (iPad)

    private var starredGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: BrandSpacing.md
            ) {
                ForEach(vm.messages) { msg in
                    StarredCard(message: msg) {
                        Task { await vm.unstar(msg) }
                    } onTap: {
                        onOpenThread?(msg.threadPhone)
                    }
                    .contextMenu {
                        Button("Open Thread") { onOpenThread?(msg.threadPhone) }
                        Button("Unstar", role: .destructive) { Task { await vm.unstar(msg) } }
                    }
#if !os(macOS)
                    .hoverEffect(.highlight)
#endif
                }
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - States

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "star")
                .font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No starred messages")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text("Long-press any message in a thread and choose Star to save it here.")
                .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load starred messages")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - StarredRow

private struct StarredRow: View {
    let message: StarredMessage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.bizarreOrange)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    if let name = message.customerName, !name.isEmpty {
                        Text(name)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                    } else {
                        Text(message.threadPhone)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    Text(message.body)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                    if let ts = message.createdAt?.prefix(10) {
                        Text(String(ts))
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.customerName ?? message.threadPhone). \(message.body)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - StarredCard (iPad)

private struct StarredCard: View {
    let message: StarredMessage
    let onUnstar: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                HStack {
                    Text(message.customerName ?? message.threadPhone)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    Spacer()
                    Button(action: onUnstar) {
                        Image(systemName: "star.slash")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unstar this message")
                }
                Text(message.body)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(4)
                Spacer()
                if let ts = message.createdAt?.prefix(10) {
                    Text(String(ts))
                        .font(.brandMono(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.customerName ?? message.threadPhone). \(message.body)")
        .accessibilityAddTraits(.isButton)
    }
}
