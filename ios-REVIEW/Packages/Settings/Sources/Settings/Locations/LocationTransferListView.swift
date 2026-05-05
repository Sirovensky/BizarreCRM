import SwiftUI
import Core
import DesignSystem

// MARK: - §60.2 LocationTransferListView

public struct LocationTransferListView: View {
    @State private var vm: LocationTransferListViewModel
    @State private var showTransferSheet: Bool = false

    public init(repo: any LocationRepository, locations: [Location], activeLocationId: String = "") {
        _vm = State(initialValue: LocationTransferListViewModel(
            repo: repo,
            locations: locations,
            activeLocationId: activeLocationId
        ))
    }

    public var body: some View {
        Group {
            switch vm.loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let msg):
                ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
            default:
                content
            }
        }
        .navigationTitle("Transfers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showTransferSheet = true
                } label: {
                    Label("New Transfer", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityLabel("New transfer")
            }
        }
        .sheet(isPresented: $showTransferSheet) {
            LocationTransferSheet(
                repo: vm.repo,
                locations: vm.locations
            ) { newTransfer in
                vm.append(newTransfer)
                showTransferSheet = false
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Direction filter
            Picker("Direction", selection: $vm.direction) {
                ForEach(TransferDirection.allCases) { dir in
                    Text(dir.displayName).tag(dir)
                }
            }
            .pickerStyle(.segmented)
            .padding(DesignTokens.Spacing.md)
            .accessibilityLabel("Filter by direction")

            if vm.filtered.isEmpty {
                ContentUnavailableView("No Transfers", systemImage: "arrow.left.arrow.right")
            } else {
                List(vm.filtered) { transfer in
                    TransferRow(transfer: transfer, locations: vm.locations)
                        .contextMenu {
                            if transfer.status == "requested" {
                                Button("Mark Shipped") {
                                    Task { await vm.updateStatus(id: transfer.id, status: "shipped") }
                                }
                            }
                            if transfer.status == "shipped" {
                                Button("Mark Received") {
                                    Task { await vm.updateStatus(id: transfer.id, status: "received") }
                                }
                            }
                        }
                }
            }
        }
    }
}

// MARK: - TransferRow

private struct TransferRow: View {
    let transfer: LocationTransferRequest
    let locations: [Location]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(fromName)
                    .font(.subheadline.bold())
                Image(systemName: "arrow.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(toName)
                    .font(.subheadline.bold())
                Spacer()
                StatusPill(
                    transfer.status.capitalized,
                    hue: statusHue(transfer.status)
                )
            }
            Text("\(transfer.items.count) item(s) · \(transfer.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("Transfer from \(fromName) to \(toName), status \(transfer.status)")
    }

    private var fromName: String {
        locations.first(where: { $0.id == transfer.fromLocationId })?.name ?? transfer.fromLocationId
    }

    private var toName: String {
        locations.first(where: { $0.id == transfer.toLocationId })?.name ?? transfer.toLocationId
    }

    private func statusHue(_ status: String) -> StatusPill.Hue {
        switch status {
        case "received": return .ready
        case "shipped":  return .awaiting
        default:         return .archived
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class LocationTransferListViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, error(String) }

    private(set) var transfers: [LocationTransferRequest] = []
    private(set) var loadState: LoadState = .idle
    let locations: [Location]
    let repo: any LocationRepository
    let activeLocationId: String
    var direction: TransferDirection = .all

    init(repo: any LocationRepository, locations: [Location], activeLocationId: String) {
        self.repo = repo
        self.locations = locations
        self.activeLocationId = activeLocationId
    }

    var filtered: [LocationTransferRequest] {
        let base = activeLocationId.isEmpty
            ? transfers
            : transfers.filter {
                $0.fromLocationId == activeLocationId || $0.toLocationId == activeLocationId
            }
        switch direction {
        case .all:      return base
        case .outgoing: return base.filter { $0.fromLocationId == activeLocationId }
        case .incoming: return base.filter { $0.toLocationId == activeLocationId }
        }
    }

    func load() async {
        loadState = .loading
        do {
            transfers = try await repo.fetchTransfers(locationId: activeLocationId.isEmpty ? nil : activeLocationId)
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    func append(_ transfer: LocationTransferRequest) {
        transfers = [transfer] + transfers
    }

    func updateStatus(id: String, status: String) async {
        do {
            let updated = try await repo.updateTransferStatus(id: id, status: status)
            transfers = transfers.map { $0.id == updated.id ? updated : $0 }
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }
}
