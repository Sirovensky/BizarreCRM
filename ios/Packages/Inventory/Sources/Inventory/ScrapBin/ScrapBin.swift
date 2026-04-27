#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §6.8 Scrap Bin (Damage / Disposal)

// MARK: Models

public enum ScrapReason: String, CaseIterable, Sendable, Identifiable, Codable {
    case damaged, obsolete, expired, lost
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

public enum DisposalMethod: String, CaseIterable, Sendable, Identifiable, Codable {
    case trash, recycle, salvage
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

public struct ScrapEntry: Identifiable, Sendable, Decodable {
    public let id: Int64
    public let inventoryId: Int64
    public let sku: String
    public let name: String
    public let qty: Int
    public let reason: ScrapReason
    public let notes: String?
    public let movedAt: String          // ISO date string
    public let costCents: Int
    public var costFormatted: String { String(format: "$%.2f", Double(costCents) / 100.0) }

    enum CodingKeys: String, CodingKey {
        case id, sku, name, qty, reason, notes
        case inventoryId = "inventory_id"
        case movedAt = "moved_at"
        case costCents = "cost_cents"
    }
}

public struct MoveToScrapRequest: Encodable, Sendable {
    public let inventoryId: Int64
    public let qty: Int
    public let reason: ScrapReason
    public let notes: String?
    public let photoBase64: String?

    enum CodingKeys: String, CodingKey {
        case qty, reason, notes
        case inventoryId = "inventory_id"
        case photoBase64 = "photo_base64"
    }
}

public struct ScrapDisposalRequest: Encodable, Sendable {
    public let entryIds: [Int64]
    public let method: DisposalMethod
    public let notes: String?
    enum CodingKeys: String, CodingKey {
        case method, notes
        case entryIds = "entry_ids"
    }
}

// MARK: Repository

public protocol ScrapBinRepository: Sendable {
    func list() async throws -> [ScrapEntry]
    func moveToScrap(_ request: MoveToScrapRequest) async throws
    func dispose(_ request: ScrapDisposalRequest) async throws
}

public actor ScrapBinRepositoryImpl: ScrapBinRepository {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func list() async throws -> [ScrapEntry] {
        try await api.listScrapBin()
    }
    public func moveToScrap(_ request: MoveToScrapRequest) async throws {
        try await api.moveToScrap(request)
    }
    public func dispose(_ request: ScrapDisposalRequest) async throws {
        try await api.disposeScrap(request)
    }
}

// MARK: ViewModel

@MainActor
@Observable
public final class ScrapBinViewModel {
    public private(set) var entries: [ScrapEntry] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var selectedIds: Set<Int64> = []
    public var showDisposalSheet = false
    public var disposalMethod: DisposalMethod = .recycle
    public var disposalNotes: String = ""

    @ObservationIgnored private let repo: ScrapBinRepository
    public init(repo: ScrapBinRepository) { self.repo = repo }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { entries = try await repo.list() }
        catch { errorMessage = error.localizedDescription }
    }

    public var totalCostCents: Int {
        entries.reduce(0) { $0 + $1.costCents }
    }

    public func dispose() async {
        guard !selectedIds.isEmpty else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await repo.dispose(
                ScrapDisposalRequest(
                    entryIds: Array(selectedIds),
                    method: disposalMethod,
                    notes: disposalNotes.isEmpty ? nil : disposalNotes
                )
            )
            entries.removeAll { selectedIds.contains($0.id) }
            selectedIds = []
            showDisposalSheet = false
            BrandHaptics.success()
        } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: Scrap Bin List View

public struct ScrapBinListView: View {
    @State private var vm: ScrapBinViewModel

    public init(repo: ScrapBinRepository) {
        _vm = State(wrappedValue: ScrapBinViewModel(repo: repo))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .navigationTitle("Scrap Bin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showDisposalSheet) { disposalSheet }
    }

    // MARK: List

    private var entryList: some View {
        List(selection: $vm.selectedIds) {
            Section("Total cost: \(vm.entries.count) items") {
                ForEach(vm.entries) { entry in
                    entryRow(entry)
                        .tag(entry.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    private func entryRow(_ entry: ScrapEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.bizarreBody)
                    .fontWeight(.medium)
                HStack {
                    Text("\(entry.qty) units")
                    Text("·")
                    Label(entry.reason.label, systemImage: "exclamationmark.triangle")
                }
                .font(.bizarreCaption)
                .foregroundStyle(Color.bizarreTextSecondary)
                if let notes = entry.notes {
                    Text(notes)
                        .font(.bizarreCaption)
                        .foregroundStyle(Color.bizarreTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(entry.costFormatted)
                    .font(.bizarreBody)
                Text(entry.movedAt.prefix(10))
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(entry.qty) units, \(entry.reason.label)")
    }

    // MARK: Disposal Sheet

    private var disposalSheet: some View {
        NavigationStack {
            Form {
                Section("\(vm.selectedIds.count) items selected") {
                    Picker("Disposal method", selection: $vm.disposalMethod) {
                        ForEach(DisposalMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    TextField("Notes (optional)", text: $vm.disposalNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Text("A disposal document with signature will be generated. This action is permanent.")
                        .font(.bizarreCaption)
                        .foregroundStyle(Color.bizarreTextSecondary)
                }
            }
            .navigationTitle("Dispose Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showDisposalSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dispose") { Task { await vm.dispose() } }
                        .disabled(vm.isLoading)
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.showDisposalSheet = true
            } label: {
                Label("Dispose", systemImage: "trash")
            }
            .disabled(vm.selectedIds.isEmpty)
            .accessibilityLabel("Dispose selected items")
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.slash")
                .font(.system(size: 44))
                .foregroundStyle(Color.bizarrePrimary)
            Text("Scrap bin is empty")
                .font(.bizarreHeadline)
            Text("Items moved to scrap via Inventory → item → Move to scrap.")
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Move to Scrap Sheet (launched from InventoryDetailView)

public struct MoveToScrapSheet: View {
    let inventoryId: Int64
    let itemName: String
    let maxQty: Int
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var qty: Int = 1
    @State private var reason: ScrapReason = .damaged
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @ObservationIgnored private let repo: ScrapBinRepository

    public init(
        inventoryId: Int64, itemName: String, maxQty: Int,
        repo: ScrapBinRepository, onComplete: @escaping () -> Void
    ) {
        self.inventoryId = inventoryId
        self.itemName = itemName
        self.maxQty = maxQty
        self.repo = repo
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Move to scrap bin — \(itemName)") {
                    Stepper("Qty: \(qty)", value: $qty, in: 1...max(1, maxQty))
                    Picker("Reason", selection: $reason) {
                        ForEach(ScrapReason.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.bizarreError)
                    }
                }
            }
            .navigationTitle("Move to Scrap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        do {
            try await repo.moveToScrap(
                MoveToScrapRequest(
                    inventoryId: inventoryId,
                    qty: qty,
                    reason: reason,
                    notes: notes.isEmpty ? nil : notes,
                    photoBase64: nil
                )
            )
            BrandHaptics.success()
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}

// MARK: - APIClient extension (§6.8 Scrap Bin)

extension APIClient {
    func listScrapBin() async throws -> [ScrapEntry] {
        let resp: APIResponse<[ScrapEntry]> = try await get("/api/v1/inventory/scrap-bin")
        return resp.data ?? []
    }

    func moveToScrap(_ request: MoveToScrapRequest) async throws {
        let _: APIResponse<EmptyScrapBody> = try await post(
            "/api/v1/inventory/scrap-bin", body: request
        )
    }

    func disposeScrap(_ request: ScrapDisposalRequest) async throws {
        let _: APIResponse<EmptyScrapBody> = try await post(
            "/api/v1/inventory/scrap-bin/dispose", body: request
        )
    }
}

private struct EmptyScrapBody: Decodable {}
#endif
