import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - WaitlistListViewModel

@MainActor
@Observable
public final class WaitlistListViewModel {
    public private(set) var entries: [WaitlistEntry] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        if entries.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            entries = try await api.listWaitlistEntries()
                .sorted { $0.createdAt < $1.createdAt }
        } catch {
            AppLog.ui.error("Waitlist load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func offer(entry: WaitlistEntry) async {
        do {
            let updated = try await api.offerWaitlistEntry(id: entry.id)
            update(updated)
        } catch {
            AppLog.ui.error("Waitlist offer failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func cancel(entry: WaitlistEntry) async {
        do {
            let updated = try await api.cancelWaitlistEntry(id: entry.id)
            update(updated)
        } catch {
            AppLog.ui.error("Waitlist cancel failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func update(_ entry: WaitlistEntry) {
        entries = entries.map { $0.id == entry.id ? entry : $0 }
    }
}

// MARK: - WaitlistListView

public struct WaitlistListView: View {
    @State private var vm: WaitlistListViewModel
    @State private var showingAdd = false
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: WaitlistListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showingAdd, onDismiss: { Task { await vm.load() } }) {
            WaitlistAddSheet(api: api)
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        NavigationStack {
            ZStack { Color.bizarreSurfaceBase.ignoresSafeArea(); content }
                .navigationTitle("Waitlist")
                .toolbar { addButton }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack { Color.bizarreSurfaceBase.ignoresSafeArea(); content }
                .navigationTitle("Waitlist")
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 540)
                .toolbar { addButton }
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 52))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Select a waitlist entry")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingAdd = true } label: { Image(systemName: "plus") }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("Add to waitlist")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            PhaseErrorView(message: err) { Task { await vm.load() } }
        } else if vm.entries.isEmpty {
            PhaseEmptyView(icon: "list.clipboard", text: "No waitlist entries")
        } else {
            List {
                ForEach(vm.entries) { entry in
                    WaitlistRow(entry: entry) {
                        Task { await vm.offer(entry: entry) }
                    } onCancel: {
                        Task { await vm.cancel(entry: entry) }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .brandHover()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - WaitlistRow

private struct WaitlistRow: View {
    let entry: WaitlistEntry
    let onOffer: () -> Void
    let onCancel: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.requestedServiceType)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Customer #\(entry.customerId)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Added \(Self.dateFormatter.string(from: entry.createdAt))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.sm) {
                StatusBadge(status: entry.status)
                if entry.status == .waiting {
                    Button("Offer", action: onOffer)
                        .font(.brandLabelSmall())
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Offer slot to customer #\(entry.customerId)")
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.requestedServiceType). Customer \(entry.customerId). \(entry.status.displayName)"
        )
        .contextMenu {
            if entry.status == .waiting {
                Button("Offer Slot", action: onOffer)
            }
            Button("Cancel", role: .destructive, action: onCancel)
        }
    }
}

private struct StatusBadge: View {
    let status: WaitlistStatus

    private var color: Color {
        switch status {
        case .waiting:   return .bizarreOnSurfaceMuted
        case .offered:   return .bizarreOrange
        case .scheduled: return Color.green
        case .canceled:  return .bizarreError
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

