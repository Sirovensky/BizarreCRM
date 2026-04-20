import Foundation
import Observation
import Core
import Networking

/// Sentinel id returned by `InventoryCreateViewModel` when the create was
/// queued for offline sync instead of persisted server-side. Callers that
/// navigate immediately to detail should not use this id — it will resolve
/// to a real server id once the drain loop succeeds.
public let PendingSyncInventoryId: Int64 = -1

@MainActor
@Observable
public final class InventoryCreateViewModel {
    // Bound to the form — strings so we can render number fields without
    // eager NSNumber parsing.
    public var name: String = ""
    public var sku: String = ""
    public var upc: String = ""
    public var itemType: String = "product"
    public var category: String = ""
    public var manufacturer: String = ""
    public var description: String = ""
    public var costPrice: String = ""
    public var retailPrice: String = ""
    public var inStock: String = ""
    public var reorderLevel: String = ""

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?
    public private(set) var queuedOffline: Bool = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    /// Minimum viable inventory row: name + sku. Without a SKU the server
    /// will auto-generate one, but `CustomerCreateView`-style UX dictates we
    /// force the operator to type one in so barcode scans stay predictable.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
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
            let created = try await api.createInventoryItem(req)
            createdId = created.id
        } catch {
            if InventoryOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Inventory create failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func buildRequest() -> CreateInventoryItemRequest {
        CreateInventoryItemRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            itemType: itemType,
            sku: trim(sku),
            upc: trim(upc),
            description: trim(description),
            category: trim(category),
            manufacturer: trim(manufacturer),
            costPrice: parseDouble(costPrice),
            retailPrice: parseDouble(retailPrice),
            inStock: parseInt(inStock),
            reorderLevel: parseInt(reorderLevel),
            supplierId: nil
        )
    }

    private func enqueueOffline(_ req: CreateInventoryItemRequest) async {
        do {
            let payload = try InventoryOfflineQueue.encode(req)
            await InventoryOfflineQueue.enqueue(op: "create", payload: payload)
            createdId = PendingSyncInventoryId
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error("Inventory create encode failed: \(error.localizedDescription, privacy: .public)")
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

public struct InventoryCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: InventoryCreateViewModel
    @State private var pendingBanner: String?

    public init(api: APIClient) {
        _vm = State(wrappedValue: InventoryCreateViewModel(api: api))
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
                isEdit: false,
                errorMessage: vm.errorMessage
            )
            .navigationTitle("New item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.queuedOffline {
                                pendingBanner = "Saved — will sync when online"
                                try? await Task.sleep(nanoseconds: 900_000_000)
                                dismiss()
                            } else if vm.createdId != nil {
                                dismiss()
                            }
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

/// Small glass banner for "Saved — will sync" — chrome only, per the
/// Liquid-Glass rule (not a row or card).
struct InventoryPendingSyncBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.icloud")
            Text(text).font(.brandLabelLarge())
        }
        .foregroundStyle(.bizarreOnSurface)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, tint: .bizarreOrange)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
#endif
