#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §6.8 Inter-Location Inventory Transfers

// MARK: Models

public enum TransferStatus: String, CaseIterable, Sendable, Identifiable, Decodable {
    case draft, inTransit = "in_transit", received, cancelled
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .draft: return "Draft"
        case .inTransit: return "In Transit"
        case .received: return "Received"
        case .cancelled: return "Cancelled"
        }
    }
    public var color: Color {
        switch self {
        case .draft: return .bizarreTextSecondary
        case .inTransit: return .bizarreWarning
        case .received: return .bizarrePrimary
        case .cancelled: return .bizarreError
        }
    }
}

public struct InventoryTransfer: Identifiable, Sendable, Decodable {
    public let id: Int64
    public let status: TransferStatus
    public let sourceLocationId: Int64
    public let sourceLocationName: String
    public let destLocationId: Int64
    public let destLocationName: String
    public let createdAt: String
    public let lines: [TransferLine]

    enum CodingKeys: String, CodingKey {
        case id, status, lines
        case sourceLocationId = "source_location_id"
        case sourceLocationName = "source_location_name"
        case destLocationId = "dest_location_id"
        case destLocationName = "dest_location_name"
        case createdAt = "created_at"
    }
}

public struct TransferLine: Identifiable, Sendable, Decodable {
    public let id: Int64
    public let inventoryId: Int64
    public let sku: String
    public let name: String
    public let qtySent: Int
    public var qtyReceived: Int
    public var discrepancy: Int { qtyReceived - qtySent }
    public var hasDiscrepancy: Bool { discrepancy != 0 }

    enum CodingKeys: String, CodingKey {
        case id, sku, name
        case inventoryId = "inventory_id"
        case qtySent = "qty_sent"
        case qtyReceived = "qty_received"
    }
}

public struct CreateTransferRequest: Encodable, Sendable {
    public let sourceLocationId: Int64
    public let destLocationId: Int64
    public let lines: [TransferLineRequest]

    enum CodingKeys: String, CodingKey {
        case lines
        case sourceLocationId = "source_location_id"
        case destLocationId = "dest_location_id"
    }
}

public struct TransferLineRequest: Encodable, Sendable {
    public let inventoryId: Int64
    public let qty: Int
    enum CodingKeys: String, CodingKey {
        case qty
        case inventoryId = "inventory_id"
    }
}

public struct FinalizeTransferRequest: Encodable, Sendable {
    public let receivedLines: [ReceivedLine]
    enum CodingKeys: String, CodingKey { case receivedLines = "received_lines" }
    public struct ReceivedLine: Encodable, Sendable {
        let lineId: Int64; let qtyReceived: Int
        enum CodingKeys: String, CodingKey { case lineId = "line_id"; case qtyReceived = "qty_received" }
    }
}

// MARK: Repository

public protocol TransferRepository: Sendable {
    func list(status: TransferStatus?) async throws -> [InventoryTransfer]
    func create(_ request: CreateTransferRequest) async throws -> InventoryTransfer
    func dispatch(id: Int64) async throws -> InventoryTransfer
    func receive(id: Int64, _ request: FinalizeTransferRequest) async throws -> InventoryTransfer
    func cancel(id: Int64) async throws
}

public actor TransferRepositoryImpl: TransferRepository {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func list(status: TransferStatus?) async throws -> [InventoryTransfer] {
        var path = "/api/v1/inventory/transfers"
        if let s = status { path += "?status=\(s.rawValue)" }
        let resp: APIResponse<[InventoryTransfer]> = try await api.get(path)
        return resp.data ?? []
    }

    public func create(_ request: CreateTransferRequest) async throws -> InventoryTransfer {
        let resp: APIResponse<InventoryTransfer> = try await api.post(
            "/api/v1/inventory/transfers", body: request
        )
        guard let t = resp.data else { throw AppError.serverError("No transfer returned") }
        return t
    }

    public func dispatch(id: Int64) async throws -> InventoryTransfer {
        struct Empty: Encodable {}
        let resp: APIResponse<InventoryTransfer> = try await api.post(
            "/api/v1/inventory/transfers/\(id)/dispatch", body: Empty()
        )
        guard let t = resp.data else { throw AppError.serverError("No transfer returned") }
        return t
    }

    public func receive(id: Int64, _ request: FinalizeTransferRequest) async throws -> InventoryTransfer {
        let resp: APIResponse<InventoryTransfer> = try await api.post(
            "/api/v1/inventory/transfers/\(id)/receive", body: request
        )
        guard let t = resp.data else { throw AppError.serverError("No transfer returned") }
        return t
    }

    public func cancel(id: Int64) async throws {
        struct Empty: Encodable {}
        let _: APIResponse<EmptyTransferBody> = try await api.post(
            "/api/v1/inventory/transfers/\(id)/cancel", body: Empty()
        )
    }
}

private struct EmptyTransferBody: Decodable {}

// MARK: ViewModel

@MainActor
@Observable
public final class TransferListViewModel {
    public private(set) var transfers: [InventoryTransfer] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var filter: TransferStatus? = nil
    public var showCreateSheet = false

    @ObservationIgnored private let repo: TransferRepository
    public init(repo: TransferRepository) { self.repo = repo }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { transfers = try await repo.list(status: filter) }
        catch { errorMessage = error.localizedDescription }
    }

    public func dispatch(id: Int64) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let updated = try await repo.dispatch(id: id)
            replace(updated)
            BrandHaptics.success()
        } catch { errorMessage = error.localizedDescription }
    }

    public func cancel(id: Int64) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await repo.cancel(id: id)
            transfers.removeAll { $0.id == id }
        } catch { errorMessage = error.localizedDescription }
    }

    private func replace(_ t: InventoryTransfer) {
        if let idx = transfers.firstIndex(where: { $0.id == t.id }) {
            transfers[idx] = t
        }
    }
}

// MARK: View

public struct TransferListView: View {
    @State private var vm: TransferListViewModel

    public init(repo: TransferRepository) {
        _vm = State(wrappedValue: TransferListViewModel(repo: repo))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.transfers.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.transfers.isEmpty {
                emptyState
            } else {
                transferList
            }
        }
        .navigationTitle("Transfers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: List

    private var transferList: some View {
        List {
            filterChips
            ForEach(vm.transfers) { transfer in
                transferRow(transfer)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", value: nil)
                ForEach(TransferStatus.allCases) { status in
                    filterChip(label: status.label, value: status)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func filterChip(label: String, value: TransferStatus?) -> some View {
        Button(label) {
            vm.filter = value
            Task { await vm.load() }
        }
        .font(.bizarreCaption)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(vm.filter == value ? Color.bizarrePrimary : Color.bizarreSurfaceElevated)
        .foregroundStyle(vm.filter == value ? Color.white : Color.bizarreTextPrimary)
        .clipShape(Capsule())
    }

    private func transferRow(_ t: InventoryTransfer) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transfer #\(t.id)")
                    .font(.bizarreBody)
                    .fontWeight(.medium)
                Text("\(t.sourceLocationName) → \(t.destLocationName)")
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
                Text("\(t.lines.count) items")
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label(t.status.label, systemImage: statusIcon(t.status))
                    .font(.bizarreCaption)
                    .foregroundStyle(t.status.color)
                if t.status == .draft {
                    Button("Dispatch") {
                        Task { await vm.dispatch(id: t.id) }
                    }
                    .font(.bizarreCaption)
                    .buttonStyle(.bordered)
                    .tint(.bizarrePrimary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if t.status == .draft {
                Button(role: .destructive) {
                    Task { await vm.cancel(id: t.id) }
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transfer \(t.id), \(t.sourceLocationName) to \(t.destLocationName), \(t.status.label)")
    }

    private func statusIcon(_ status: TransferStatus) -> String {
        switch status {
        case .draft: return "doc"
        case .inTransit: return "shippingbox"
        case .received: return "checkmark.circle"
        case .cancelled: return "xmark.circle"
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { vm.showCreateSheet = true } label: {
                Label("New transfer", systemImage: "plus")
            }
            .accessibilityLabel("Create transfer")
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 44))
                .foregroundStyle(Color.bizarrePrimary)
            Text("No transfers")
                .font(.bizarreHeadline)
            Text("Create a transfer to move inventory between locations.")
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("New Transfer") { vm.showCreateSheet = true }
                .buttonStyle(.brandPrimary)
        }
    }
}
#endif
