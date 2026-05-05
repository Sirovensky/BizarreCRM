#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.4 Move item between locations
//
// Presents a location picker (loaded from GET /api/v1/locations) + qty stepper,
// then creates an inventory transfer via POST /api/v1/inventory/transfers.
// Used from InventoryDetailView when the item has multi-location tenants.

// MARK: - Minimal location DTO (Inventory-local; avoids Settings package dependency)

public struct InventoryLocation: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let active: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, active
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// GET /api/v1/locations — returns all tenant locations (active only, for transfer picker).
    func inventoryTransferLocations() async throws -> [InventoryLocation] {
        do {
            return try await get("/api/v1/locations", as: [InventoryLocation].self)
        } catch {
            // 404/501 = multi-location not enabled; return empty
            let msg = error.localizedDescription.lowercased()
            if msg.contains("404") || msg.contains("501") || msg.contains("not found") {
                return []
            }
            throw error
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class MoveToLocationViewModel {
    public private(set) var locations: [InventoryLocation] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSucceed: Bool = false

    public var selectedLocationId: String? = nil
    public var qty: Int = 1

    private let itemId: Int64
    private let itemName: String
    public let currentStock: Int
    private let api: APIClient

    public init(itemId: Int64, itemName: String, currentStock: Int, api: APIClient) {
        self.itemId = itemId
        self.itemName = itemName
        self.currentStock = currentStock
        self.api = api
    }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            locations = try await api.inventoryTransferLocations()
                .filter(\.active)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var maxQty: Int { max(1, currentStock) }
    public var canSubmit: Bool { selectedLocationId != nil && qty > 0 && qty <= maxQty }

    public func submit(sourceLocationId: Int64) async {
        guard let destId = selectedLocationId,
              let destIdInt = Int64(destId),
              canSubmit else { return }
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let req = CreateTransferRequest(
            sourceLocationId: sourceLocationId,
            destLocationId: destIdInt,
            lines: [TransferLineRequest(inventoryId: itemId, qty: qty)]
        )
        do {
            let repo = TransferRepositoryImpl(api: api)
            let transfer = try await repo.create(req)
            // Auto-dispatch so it moves immediately (single-item move from detail)
            _ = try await repo.dispatch(id: transfer.id)
            didSucceed = true
            BrandHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

/// Quick "Move to location" sheet — shown from InventoryDetailView secondary action.
public struct MoveToLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: MoveToLocationViewModel

    /// The source location ID of the current item (from LocationContext or item detail).
    private let sourceLocationId: Int64

    public init(
        itemId: Int64,
        itemName: String,
        currentStock: Int,
        sourceLocationId: Int64,
        api: APIClient
    ) {
        self.sourceLocationId = sourceLocationId
        _vm = State(wrappedValue: MoveToLocationViewModel(
            itemId: itemId,
            itemName: itemName,
            currentStock: currentStock,
            api: api
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Move to Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Moving…" : "Move") {
                        Task { await vm.submit(sourceLocationId: sourceLocationId) }
                    }
                    .disabled(!vm.canSubmit || vm.isSubmitting)
                    .accessibilityLabel(vm.isSubmitting ? "Moving stock" : "Confirm move to location")
                }
            }
            .task { await vm.load() }
            .onChange(of: vm.didSucceed) { _, didSucceed in
                if didSucceed { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Loading locations…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(err)
        } else if vm.locations.filter({ $0.id != String(sourceLocationId) }).isEmpty {
            emptyState
        } else {
            Form {
                Section("Destination") {
                    Picker("Location", selection: $vm.selectedLocationId) {
                        Text("Choose…").tag(Optional<String>.none)
                        ForEach(vm.locations.filter { $0.id != String(sourceLocationId) }) { loc in
                            Text(loc.name).tag(Optional(loc.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Quantity to move") {
                    Stepper("\(vm.qty) unit\(vm.qty == 1 ? "" : "s")", value: $vm.qty, in: 1...vm.maxQty)
                        .accessibilityLabel("Quantity to move: \(vm.qty)")
                    Text("Available: \(vm.currentStock)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if let err = vm.errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.bizarreError)
                            Text(err)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreError)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No other locations")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Add more locations in Settings to transfer stock.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load locations")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .padding()
    }
}
#endif
