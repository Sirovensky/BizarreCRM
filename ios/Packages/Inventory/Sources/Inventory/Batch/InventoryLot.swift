import Foundation
import Networking
import Core

// MARK: - §6.8 Batch / Lot Tracking

// MARK: Models

public enum LotDecrementPolicy: String, CaseIterable, Sendable, Identifiable {
    case fifo, lifo, fefo
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .fifo: return "FIFO (oldest first)"
        case .lifo: return "LIFO (newest first)"
        case .fefo: return "FEFO (expiry first)"
        }
    }
}

public struct InventoryLot: Identifiable, Sendable, Decodable, Hashable {
    public let id: Int64
    public let parentSku: String
    public let lotId: String
    public let receiveDate: String        // ISO date string
    public let vendorInvoice: String?
    public let qty: Int
    public let expiry: String?            // ISO date string, optional

    public var expiryDate: Date? {
        guard let e = expiry else { return nil }
        return ISO8601DateFormatter().date(from: e)
    }

    public var isExpired: Bool {
        guard let d = expiryDate else { return false }
        return d < Date()
    }

    public var isNearExpiry: Bool {
        guard let d = expiryDate else { return false }
        let days30 = Date().addingTimeInterval(30 * 86400)
        return d < days30 && !isExpired
    }

    enum CodingKeys: String, CodingKey {
        case id, qty, expiry
        case parentSku = "parent_sku"
        case lotId = "lot_id"
        case receiveDate = "receive_date"
        case vendorInvoice = "vendor_invoice"
    }
}

public struct LotRecallQuery: Encodable, Sendable {
    public let lotId: String
    enum CodingKeys: String, CodingKey { case lotId = "lot_id" }
}

public struct LotRecallResult: Sendable, Decodable {
    public let lotId: String
    public let affectedTickets: [RecallAffectedTicket]
    enum CodingKeys: String, CodingKey {
        case lotId = "lot_id"
        case affectedTickets = "affected_tickets"
    }
}

public struct RecallAffectedTicket: Identifiable, Sendable, Decodable {
    public let id: Int64
    public let ticketNumber: String
    public let customerName: String?
    public let partName: String
    enum CodingKeys: String, CodingKey {
        case id
        case ticketNumber = "ticket_number"
        case customerName = "customer_name"
        case partName = "part_name"
    }
}

// MARK: Pure Decrement Selector

public enum LotDecrementSelector {
    /// Returns ordered lots to consume first given a policy and quantity needed.
    public static func selectLots(
        from lots: [InventoryLot],
        qty needed: Int,
        policy: LotDecrementPolicy
    ) -> [LotDecrement] {
        let ordered = sorted(lots, by: policy)
        var remaining = needed
        var decrements: [LotDecrement] = []
        for lot in ordered where remaining > 0 {
            let take = min(lot.qty, remaining)
            decrements.append(LotDecrement(lotId: lot.lotId, qty: take))
            remaining -= take
        }
        return decrements
    }

    private static func sorted(_ lots: [InventoryLot], by policy: LotDecrementPolicy) -> [InventoryLot] {
        switch policy {
        case .fifo:
            return lots.sorted { $0.receiveDate < $1.receiveDate }
        case .lifo:
            return lots.sorted { $0.receiveDate > $1.receiveDate }
        case .fefo:
            return lots.sorted { lhs, rhs in
                switch (lhs.expiryDate, rhs.expiryDate) {
                case (nil, nil): return lhs.receiveDate < rhs.receiveDate
                case (nil, _): return false
                case (_, nil): return true
                case (let l?, let r?): return l < r
                }
            }
        }
    }
}

public struct LotDecrement: Sendable {
    public let lotId: String
    public let qty: Int
}

// MARK: Repository Protocol

public protocol LotRepository: Sendable {
    func lots(forSku sku: String) async throws -> [InventoryLot]
    func recall(lotId: String) async throws -> LotRecallResult
}

public actor LotRepositoryImpl: LotRepository {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func lots(forSku sku: String) async throws -> [InventoryLot] {
        try await api.listLots(sku: sku)
    }

    public func recall(lotId: String) async throws -> LotRecallResult {
        try await api.lotRecall(lotId: lotId)
    }
}

// MARK: ViewModel

#if canImport(UIKit)
import SwiftUI
import DesignSystem

@MainActor
@Observable
public final class LotTrackingViewModel {
    public private(set) var lots: [InventoryLot] = []
    public private(set) var recallResult: LotRecallResult?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var policy: LotDecrementPolicy = .fifo
    public var showRecallSheet = false
    public var selectedLotId: String?

    @ObservationIgnored private let repo: LotRepository
    @ObservationIgnored private let sku: String

    public init(repo: LotRepository, sku: String) {
        self.repo = repo
        self.sku = sku
    }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { lots = try await repo.lots(forSku: sku) }
        catch { errorMessage = error.localizedDescription }
    }

    public func runRecall(lotId: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            recallResult = try await repo.recall(lotId: lotId)
            showRecallSheet = true
        } catch { errorMessage = error.localizedDescription }
    }

    public var decrementPreview: [LotDecrement] {
        LotDecrementSelector.selectLots(from: lots, qty: 1, policy: policy)
    }
}

// MARK: View

public struct LotTrackingView: View {
    @State private var vm: LotTrackingViewModel

    public init(repo: LotRepository, sku: String) {
        _vm = State(wrappedValue: LotTrackingViewModel(repo: repo, sku: sku))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.lots.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.lots.isEmpty {
                emptyState
            } else {
                lotList
            }
        }
        .navigationTitle("Lot Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { policyPicker }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showRecallSheet) { recallSheet }
    }

    // MARK: List

    private var lotList: some View {
        List {
            Section("Lots") {
                ForEach(vm.lots) { lot in
                    lotRow(lot)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func lotRow(_ lot: InventoryLot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(lot.lotId)
                        .font(.bizarreBody)
                        .fontWeight(.medium)
                    if lot.isExpired {
                        Label("Expired", systemImage: "exclamationmark.triangle.fill")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreError)
                    } else if lot.isNearExpiry {
                        Label("Near expiry", systemImage: "clock.badge.exclamationmark")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreWarning)
                    }
                }
                HStack {
                    Text("Received: \(lot.receiveDate)")
                    if let inv = lot.vendorInvoice { Text("· Inv: \(inv)") }
                }
                .font(.bizarreCaption)
                .foregroundStyle(Color.bizarreTextSecondary)
                if let expiry = lot.expiry {
                    Text("Expiry: \(expiry)")
                        .font(.bizarreCaption)
                        .foregroundStyle(lot.isExpired ? Color.bizarreError : Color.bizarreTextSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(lot.qty)")
                    .font(.bizarreTitle3)
                    .fontWeight(.semibold)
                Text("units")
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
            }
        }
        .swipeActions {
            Button {
                Task { await vm.runRecall(lotId: lot.lotId) }
            } label: {
                Label("Recall", systemImage: "exclamationmark.shield")
            }
            .tint(.bizarreError)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lot \(lot.lotId), \(lot.qty) units\(lot.isExpired ? ", expired" : "")")
    }

    // MARK: Recall Sheet

    private var recallSheet: some View {
        NavigationStack {
            if let result = vm.recallResult {
                List {
                    Section("Lot \(result.lotId) — \(result.affectedTickets.count) affected tickets") {
                        ForEach(result.affectedTickets) { ticket in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ticket #\(ticket.ticketNumber)")
                                    .font(.bizarreBody)
                                if let c = ticket.customerName {
                                    Text(c)
                                        .font(.bizarreCaption)
                                        .foregroundStyle(Color.bizarreTextSecondary)
                                }
                                Text(ticket.partName)
                                    .font(.bizarreCaption)
                                    .foregroundStyle(Color.bizarreTextSecondary)
                            }
                        }
                    }
                    Section {
                        Text("Contact these customers to arrange part replacement.")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Recall: Lot \(result.lotId)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { vm.showRecallSheet = false }
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var policyPicker: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(LotDecrementPolicy.allCases) { policy in
                    Button(policy.label) { vm.policy = policy }
                }
            } label: {
                Label("Policy: \(vm.policy.rawValue.uppercased())", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Select decrement policy")
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44))
                .foregroundStyle(Color.bizarrePrimary)
            Text("No lots recorded")
                .font(.bizarreHeadline)
            Text("Lot tracking records are created on receiving.")
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
        }
    }
}

// MARK: - APIClient extensions (§6.8 Lot tracking)

extension APIClient {
    func listLots(sku: String) async throws -> [InventoryLot] {
        let encoded = sku.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sku
        let resp: APIResponse<[InventoryLot]> = try await get(
            "/api/v1/inventory/lots?parent_sku=\(encoded)"
        )
        return resp.data ?? []
    }

    func lotRecall(lotId: String) async throws -> LotRecallResult {
        let encoded = lotId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? lotId
        let resp: APIResponse<LotRecallResult> = try await get(
            "/api/v1/inventory/lots/recall?lot_id=\(encoded)"
        )
        guard let result = resp.data else { throw AppError.serverError("No recall data") }
        return result
    }
}
#endif
