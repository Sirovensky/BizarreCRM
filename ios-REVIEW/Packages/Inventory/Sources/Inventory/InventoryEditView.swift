import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class InventoryEditViewModel {
    public let itemId: Int64

    public var name: String
    public var sku: String
    public var upc: String
    public var itemType: String
    public var category: String
    public var manufacturer: String
    public var description: String
    public var costPrice: String
    public var retailPrice: String
    public var inStock: String          // read-only on edit (adjust-stock endpoint)
    public var reorderLevel: String

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSave: Bool = false
    public private(set) var queuedOffline: Bool = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient, item: InventoryItemDetail) {
        self.api = api
        self.itemId = item.id
        self.name = item.name ?? ""
        self.sku = item.sku ?? ""
        self.upc = item.upcCode ?? ""
        self.itemType = item.itemType ?? "product"
        self.category = ""          // detail response doesn't carry category; leave editable but empty.
        self.manufacturer = item.manufacturerName ?? ""
        self.description = item.description ?? ""
        self.costPrice = item.costPrice.map { String(format: "%.2f", $0) } ?? ""
        self.retailPrice = item.retailPrice.map { String(format: "%.2f", $0) } ?? ""
        self.inStock = item.inStock.map { String($0) } ?? ""
        self.reorderLevel = item.reorderLevel.map { String($0) } ?? ""
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        didSave = false
        queuedOffline = false

        guard isValid else {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Name is required."
            } else {
                errorMessage = "SKU is required."
            }
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let req = buildRequest()

        do {
            _ = try await api.updateInventoryItem(id: itemId, req)
            didSave = true
        } catch {
            if InventoryOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Inventory update failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func buildRequest() -> UpdateInventoryItemRequest {
        UpdateInventoryItemRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            itemType: itemType,
            sku: trim(sku),
            upc: trim(upc),
            description: trim(description),
            category: trim(category),
            manufacturer: trim(manufacturer),
            costPrice: parseDouble(costPrice),
            retailPrice: parseDouble(retailPrice),
            reorderLevel: parseInt(reorderLevel),
            supplierId: nil
        )
    }

    private func enqueueOffline(_ req: UpdateInventoryItemRequest) async {
        do {
            let payload = try InventoryOfflineQueue.encode(req)
            await InventoryOfflineQueue.enqueue(
                op: "update",
                entityServerId: itemId,
                payload: payload
            )
            didSave = true
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error("Inventory update encode failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func trim(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func parseDouble(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Double(t)
    }

    private func parseInt(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Int(t)
    }
}

#if canImport(UIKit)
import SwiftUI
import DesignSystem

public struct InventoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: InventoryEditViewModel
    @State private var pendingBanner: String?
    private let onSaved: () -> Void

    public init(api: APIClient, item: InventoryItemDetail, onSaved: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: InventoryEditViewModel(api: api, item: item))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            InventoryFormView(
                name: $vm.name,
                sku: $vm.sku,
                upc: $vm.upc,
                itemType: $vm.itemType,
                category: $vm.category,
                manufacturer: $vm.manufacturer,
                description: $vm.description,
                costPrice: $vm.costPrice,
                retailPrice: $vm.retailPrice,
                inStock: $vm.inStock,
                reorderLevel: $vm.reorderLevel,
                isEdit: true,
                errorMessage: vm.errorMessage
            )
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            guard vm.didSave else { return }
                            onSaved()
                            if vm.queuedOffline {
                                pendingBanner = "Saved — will sync when online"
                                try? await Task.sleep(nanoseconds: 900_000_000)
                            }
                            dismiss()
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .overlay(alignment: .top) {
                if let banner = pendingBanner {
                    InventoryPendingSyncBanner(text: banner)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                }
            }
        }
    }
}
#endif
