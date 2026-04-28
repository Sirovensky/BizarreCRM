#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §6.8 Bin Location Manager

// MARK: Models

public struct BinLocation: Identifiable, Hashable, Sendable, Decodable {
    public let id: Int64
    public let aisle: String
    public let shelf: String
    public let position: String
    public let label: String

    public init(id: Int64, aisle: String, shelf: String, position: String) {
        self.id = id
        self.aisle = aisle
        self.shelf = shelf
        self.position = position
        self.label = "\(aisle)-\(shelf)-\(position)"
    }

    /// Formatted display label, e.g. "A-3-2".
    public var displayLabel: String { label }
}

public struct BinLocationCreateRequest: Encodable, Sendable {
    public let aisle: String
    public let shelf: String
    public let position: String
}

public struct BinAssignRequest: Encodable, Sendable {
    public let itemIds: [Int64]
    public let binLocationId: Int64
    enum CodingKeys: String, CodingKey {
        case itemIds = "item_ids"
        case binLocationId = "bin_location_id"
    }
}

public struct PickListEntry: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let binLabel: String
    public let sku: String
    public let itemName: String
    public let qtyNeeded: Int
    public var qtyPicked: Int
    public var isPicked: Bool { qtyPicked >= qtyNeeded }
}

// MARK: Repository

public protocol BinLocationRepository: Sendable {
    func list() async throws -> [BinLocation]
    func create(_ request: BinLocationCreateRequest) async throws -> BinLocation
    func delete(id: Int64) async throws
    func batchAssign(_ request: BinAssignRequest) async throws
}

public actor BinLocationRepositoryImpl: BinLocationRepository {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func list() async throws -> [BinLocation] {
        try await api.listBinLocations()
    }
    public func create(_ request: BinLocationCreateRequest) async throws -> BinLocation {
        try await api.createBinLocation(request)
    }
    public func delete(id: Int64) async throws {
        try await api.deleteBinLocation(id: id)
    }
    public func batchAssign(_ request: BinAssignRequest) async throws {
        try await api.batchAssignBinLocation(request)
    }
}

// MARK: ViewModel

@MainActor
@Observable
public final class BinLocationManagerViewModel {
    public private(set) var binLocations: [BinLocation] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var aisle: String = ""
    public var shelf: String = ""
    public var position: String = ""
    public var showCreateSheet = false
    public var showBatchAssignSheet = false
    public var selectedBinId: Int64?
    public var selectedItemIds: Set<Int64> = []

    @ObservationIgnored private let repo: BinLocationRepository

    public init(repo: BinLocationRepository) { self.repo = repo }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { binLocations = try await repo.list() }
        catch { errorMessage = error.localizedDescription }
    }

    public func create() async {
        guard !aisle.isEmpty, !shelf.isEmpty, !position.isEmpty else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let bin = try await repo.create(
                BinLocationCreateRequest(aisle: aisle, shelf: shelf, position: position)
            )
            binLocations.append(bin)
            aisle = ""; shelf = ""; position = ""
            showCreateSheet = false
        } catch { errorMessage = error.localizedDescription }
    }

    public func delete(id: Int64) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await repo.delete(id: id)
            binLocations.removeAll { $0.id == id }
        } catch { errorMessage = error.localizedDescription }
    }

    public func batchAssign() async {
        guard let binId = selectedBinId, !selectedItemIds.isEmpty else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await repo.batchAssign(
                BinAssignRequest(itemIds: Array(selectedItemIds), binLocationId: binId)
            )
            showBatchAssignSheet = false
            selectedItemIds = []
        } catch { errorMessage = error.localizedDescription }
    }

    /// Generate a simple pick list ordered by bin label.
    public func pickList(for entries: [PickListEntry]) -> [PickListEntry] {
        entries.sorted { $0.binLabel < $1.binLabel }
    }
}

// MARK: - Bin Location Manager View

public struct BinLocationManagerView: View {
    @State private var vm: BinLocationManagerViewModel
    @Environment(\.dismiss) private var dismiss

    public init(repo: BinLocationRepository) {
        _vm = State(wrappedValue: BinLocationManagerViewModel(repo: repo))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Bin Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .task { await vm.load() }
            .sheet(isPresented: $vm.showCreateSheet) { createSheet }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.binLocations.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.binLocations.isEmpty {
            emptyState
        } else {
            binList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 44))
                .foregroundStyle(Color.bizarrePrimary)
            Text("No bin locations yet")
                .font(.bizarreHeadline)
            Text("Create aisles, shelves and positions to organise your stock.")
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Add bin location") { vm.showCreateSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .accessibilityElement(children: .combine)
    }

    private var binList: some View {
        List {
            ForEach(vm.binLocations.sorted(by: { $0.displayLabel < $1.displayLabel })) { bin in
                HStack {
                    Label(bin.displayLabel, systemImage: "archivebox.fill")
                        .font(.bizarreBody)
                        .accessibilityLabel("Bin \(bin.displayLabel)")
                    Spacer()
                    Text("Aisle \(bin.aisle)")
                        .font(.bizarreCaption)
                        .foregroundStyle(Color.bizarreTextSecondary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await vm.delete(id: bin.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.showCreateSheet = true
            } label: {
                Label("Add bin", systemImage: "plus")
            }
            .accessibilityLabel("Add bin location")
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }

    // MARK: Create Sheet

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    LabeledContent("Aisle") {
                        TextField("e.g. A", text: $vm.aisle)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Aisle")
                    }
                    LabeledContent("Shelf") {
                        TextField("e.g. 3", text: $vm.shelf)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Shelf")
                    }
                    LabeledContent("Position") {
                        TextField("e.g. 2", text: $vm.position)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Position")
                    }
                }
                Section {
                    Text("Label preview: \(vm.aisle.isEmpty ? "A" : vm.aisle)-\(vm.shelf.isEmpty ? "1" : vm.shelf)-\(vm.position.isEmpty ? "1" : vm.position)")
                        .font(.bizarreBody)
                        .foregroundStyle(Color.bizarreTextSecondary)
                }
            }
            .navigationTitle("New Bin Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await vm.create() } }
                        .disabled(vm.aisle.isEmpty || vm.shelf.isEmpty || vm.position.isEmpty || vm.isLoading)
                }
            }
        }
    }
}

// MARK: - Pick List View

public struct BinPickListView: View {
    @State private var entries: [PickListEntry]
    @State private var pickedSet: Set<UUID> = []

    public init(entries: [PickListEntry]) {
        _entries = State(wrappedValue: entries.sorted { $0.binLabel < $1.binLabel })
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    pickRow(entry)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pick List")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func pickRow(_ entry: PickListEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: pickedSet.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(pickedSet.contains(entry.id) ? Color.bizarrePrimary : Color.bizarreTextSecondary)
                .font(.title3)
                .accessibilityLabel(pickedSet.contains(entry.id) ? "Picked" : "Not picked")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.itemName)
                    .font(.bizarreBody)
                    .fontWeight(.medium)
                HStack {
                    Label(entry.binLabel, systemImage: "archivebox")
                    Text("·")
                    Text(entry.sku)
                }
                .font(.bizarreCaption)
                .foregroundStyle(Color.bizarreTextSecondary)
            }
            Spacer()
            Text("\(entry.qtyNeeded) needed")
                .font(.bizarreCaption)
                .foregroundStyle(Color.bizarreTextSecondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            BrandHaptics.tap()
            if pickedSet.contains(entry.id) { pickedSet.remove(entry.id) }
            else { pickedSet.insert(entry.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - APIClient extensions (§6.8 Bin Locations)

extension APIClient {
    func listBinLocations() async throws -> [BinLocation] {
        try await get("/api/v1/inventory/bin-locations", as: [BinLocation].self)
    }

    func createBinLocation(_ request: BinLocationCreateRequest) async throws -> BinLocation {
        try await post("/api/v1/inventory/bin-locations", body: request, as: BinLocation.self)
    }

    func deleteBinLocation(id: Int64) async throws {
        try await delete("/api/v1/inventory/bin-locations/\(id)")
    }

    func batchAssignBinLocation(_ request: BinAssignRequest) async throws {
        _ = try await post(
            "/api/v1/inventory/bin-locations/batch-assign",
            body: request,
            as: EmptyBinBody.self
        )
    }
}

private struct EmptyBinBody: Decodable, Sendable {}
#endif
