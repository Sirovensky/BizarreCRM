import Foundation
import Observation
import Core
import Networking

/// Sentinel id returned by `InventoryCreateViewModel` when the create was
/// queued for offline sync instead of persisted server-side. Callers that
/// navigate immediately to detail should not use this id — it will resolve
/// to a real server id once the drain loop succeeds.
public let PendingSyncInventoryId: Int64 = -1

/// Draft autosave key stored in UserDefaults so an interrupted create can
/// resume from where the operator left off.
private let kInventoryDraftKey = "inventory.create.draft"

// MARK: - Draft

private struct InventoryDraft: Codable {
    var name: String = ""
    var sku: String = ""
    var upc: String = ""
    var itemType: String = "product"
    var category: String = ""
    var manufacturer: String = ""
    var description: String = ""
    var costPriceCents: String = ""
    var retailPriceCents: String = ""
    var inStock: String = ""
    var reorderLevel: String = ""
    var supplierId: String = ""
}

// MARK: - ViewModel

@MainActor
@Observable
public final class InventoryCreateViewModel {
    // Bound to the form
    public var name: String = "" { didSet { saveDraft() } }
    public var sku: String = "" { didSet { saveDraft() } }
    public var upc: String = "" { didSet { saveDraft() } }
    public var itemType: String = "product" { didSet { saveDraft() } }
    public var category: String = "" { didSet { saveDraft() } }
    public var manufacturer: String = "" { didSet { saveDraft() } }
    public var description: String = "" { didSet { saveDraft() } }
    /// Cost expressed in dollars.cents as a string.
    public var costPriceCents: String = "" { didSet { saveDraft() } }
    /// Retail expressed in dollars.cents as a string.
    public var retailPriceCents: String = "" { didSet { saveDraft() } }
    public var inStock: String = "" { didSet { saveDraft() } }
    public var reorderLevel: String = "" { didSet { saveDraft() } }
    public var supplierId: String = "" { didSet { saveDraft() } }

    /// Photo data URLs waiting to be uploaded after the item is created.
    public var pendingPhotos: [Data] = []

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?
    public private(set) var queuedOffline: Bool = false
    public private(set) var hasDraft: Bool = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        loadDraft()
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Auto-map a scanned barcode string to the SKU field.
    public func applyBarcode(_ value: String) {
        sku = value
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        queuedOffline = false

        guard isValid else {
            errorMessage = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Name is required."
                : "SKU is required."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let req = buildRequest()

        do {
            let created = try await api.createInventoryItem(req)
            createdId = created.id
            clearDraft()
        } catch {
            if InventoryOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Inventory create failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Reset all form fields so the user can immediately add another item.
    public func resetForAddAnother() {
        name = ""
        sku = ""
        upc = ""
        category = ""
        manufacturer = ""
        description = ""
        costPriceCents = ""
        retailPriceCents = ""
        inStock = ""
        reorderLevel = ""
        supplierId = ""
        pendingPhotos = []
        createdId = nil
        queuedOffline = false
        errorMessage = nil
        clearDraft()
    }

    // MARK: Draft

    private func loadDraft() {
        guard let data = UserDefaults.standard.data(forKey: kInventoryDraftKey),
              let draft = try? JSONDecoder().decode(InventoryDraft.self, from: data)
        else { return }
        name = draft.name
        sku = draft.sku
        upc = draft.upc
        itemType = draft.itemType
        category = draft.category
        manufacturer = draft.manufacturer
        description = draft.description
        costPriceCents = draft.costPriceCents
        retailPriceCents = draft.retailPriceCents
        inStock = draft.inStock
        reorderLevel = draft.reorderLevel
        supplierId = draft.supplierId
        // Only consider non-empty draft as having data
        hasDraft = !name.isEmpty || !sku.isEmpty
    }

    private func saveDraft() {
        let draft = InventoryDraft(
            name: name, sku: sku, upc: upc, itemType: itemType,
            category: category, manufacturer: manufacturer,
            description: description, costPriceCents: costPriceCents,
            retailPriceCents: retailPriceCents, inStock: inStock,
            reorderLevel: reorderLevel, supplierId: supplierId
        )
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: kInventoryDraftKey)
        hasDraft = !name.isEmpty || !sku.isEmpty
    }

    public func clearDraft() {
        UserDefaults.standard.removeObject(forKey: kInventoryDraftKey)
        hasDraft = false
    }

    // MARK: Private helpers

    private func buildRequest() -> CreateInventoryItemRequest {
        CreateInventoryItemRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            itemType: itemType,
            sku: trim(sku),
            upc: trim(upc),
            description: trim(description),
            category: trim(category),
            manufacturer: trim(manufacturer),
            costPrice: parseCents(costPriceCents),
            retailPrice: parseCents(retailPriceCents),
            inStock: parseInt(inStock),
            reorderLevel: parseInt(reorderLevel),
            supplierId: parseInt64(supplierId)
        )
    }

    private func enqueueOffline(_ req: CreateInventoryItemRequest) async {
        do {
            let payload = try InventoryOfflineQueue.encode(req)
            await InventoryOfflineQueue.enqueue(op: "create", payload: payload)
            createdId = PendingSyncInventoryId
            queuedOffline = true
            errorMessage = nil
            clearDraft()
        } catch {
            AppLog.sync.error("Inventory create encode failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func trim(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Parse a dollar-amount string into a Double (server expects dollars not cents).
    private func parseCents(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Double(t)
    }

    private func parseInt(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Int(t)
    }

    private func parseInt64(_ s: String) -> Int64? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Int64(t)
    }
}

// MARK: - View

#if canImport(UIKit)
import SwiftUI
import DesignSystem

public struct InventoryCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: InventoryCreateViewModel
    @State private var pendingBanner: String?
    @State private var showingBarcodeScanner: Bool = false
    @State private var showingPhotoPicker: Bool = false
    /// True when "Save & add another" was tapped — resets form instead of dismissing.
    @State private var saveAndAddAnother: Bool = false

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: InventoryCreateViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            inventoryCreateForm
                .navigationTitle("New item")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .accessibilityLabel("Cancel new item")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(vm.isSubmitting ? "Saving…" : "Save") {
                            saveAndAddAnother = false
                            Task { await saveItem() }
                        }
                        .disabled(!vm.isValid || vm.isSubmitting)
                        .accessibilityLabel(vm.isSubmitting ? "Saving item" : "Save item")
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
        .sheet(isPresented: $showingBarcodeScanner) {
            InventoryBarcodeScanSheet { scanned in
                vm.applyBarcode(scanned)
                showingBarcodeScanner = false
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            InventoryPhotoPickerSheet { data in
                vm.pendingPhotos.append(data)
                showingPhotoPicker = false
            }
        }
    }

    private var inventoryCreateForm: some View {
        InventoryFullFormView(
            name: $vm.name,
            sku: $vm.sku,
            upc: $vm.upc,
            itemType: $vm.itemType,
            category: $vm.category,
            manufacturer: $vm.manufacturer,
            description: $vm.description,
            costPriceCents: $vm.costPriceCents,
            retailPriceCents: $vm.retailPriceCents,
            inStock: $vm.inStock,
            reorderLevel: $vm.reorderLevel,
            supplierId: $vm.supplierId,
            pendingPhotos: $vm.pendingPhotos,
            isEdit: false,
            errorMessage: vm.errorMessage,
            onScanBarcode: { showingBarcodeScanner = true },
            onAddPhoto: { showingPhotoPicker = true },
            onSaveAndAddAnother: {
                saveAndAddAnother = true
                Task { await saveItem() }
            }
        )
    }

    // MARK: - Save helper

    private func saveItem() async {
        await vm.submit()
        if vm.queuedOffline {
            pendingBanner = "Saved — will sync when online"
            if saveAndAddAnother {
                try? await Task.sleep(nanoseconds: 600_000_000)
                vm.resetForAddAnother()
                pendingBanner = nil
            } else {
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            }
        } else if vm.createdId != nil {
            if saveAndAddAnother {
                vm.resetForAddAnother()
            } else {
                dismiss()
            }
        }
        // Errors stay visible in the form.
    }
}

// MARK: - Pending sync banner

struct InventoryPendingSyncBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.icloud")
                .accessibilityHidden(true)
            Text(text).font(.brandLabelLarge())
        }
        .foregroundStyle(.bizarreOnSurface)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, tint: .bizarreOrange)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Inline barcode scan sheet

/// A minimal barcode scan sheet that wraps VisionKit DataScannerViewController.
/// Delivers the first recognised barcode string and dismisses itself.
struct InventoryBarcodeScanSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                // DataScannerViewController is UIKit-only and lives in the Camera
                // package at §17.2. We use the lightweight UIViewControllerRepresentable
                // wrapper here within the Inventory package to avoid a Camera dependency.
                InventoryDataScannerView { value in
                    onScan(value)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel barcode scan")
                }
            }
        }
    }
}

// MARK: - Photo picker sheet

/// Lightweight photo picker sheet — presents UIImagePickerController.
/// Phase 5 Camera package will replace this with an AVCaptureSession view.
struct InventoryPhotoPickerSheet: View {
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InventoryImagePickerView { data in
                onPhoto(data)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Add photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel photo picker")
                }
            }
        }
    }
}
#endif
