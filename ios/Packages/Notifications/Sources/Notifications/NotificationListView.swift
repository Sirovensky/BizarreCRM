import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class NotificationListViewModel {
    public private(set) var items: [NotificationItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            items = try await api.listNotifications()
        } catch {
            AppLog.ui.error("Notifications load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct NotificationListView: View {
    @State private var vm: NotificationListViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: NotificationListViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Notifications")
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if let err = vm.errorMessage { errorPane(err) }
        else if vm.items.isEmpty {
            emptyState(icon: "bell.slash", text: "You're all caught up")
        } else {
            List {
                ForEach(vm.items) { note in
                    Row(note: note)
                        .listRowBackground(Color.bizarreSurface1)
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
                        Text(String(ts.prefix(16)))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                if !note.read {
                    Circle().fill(Color.bizarreMagenta).frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, BrandSpacing.xs)
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
    }
}
