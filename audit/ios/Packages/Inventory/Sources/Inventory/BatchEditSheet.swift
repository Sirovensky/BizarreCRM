import Foundation
import Observation
import Core
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class BatchEditViewModel {
    /// The inventory item ids selected by the operator.
    public let selectedIds: [Int64]

    // Edit fields
    public var priceAdjustPercent: String = ""
    public var reassignCategory: String = ""
    public var newTags: String = ""

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var result: Int?  // updated count

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient, selectedIds: [Int64]) {
        self.api = api
        self.selectedIds = selectedIds
    }

    public var hasAnyField: Bool {
        !priceAdjustPercent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !reassignCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !newTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - §6.1 Bulk delete

    public private(set) var deleteResult: Int?

    public func bulkDelete() async {
        guard !isSubmitting, !selectedIds.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let req = BatchInventoryRequest(
            ids: selectedIds,
            updates: BatchInventoryUpdates(priceAdjustPercent: nil, category: nil, tags: nil)
        )
        do {
            _ = try await api.batchDeleteInventory(req)
            deleteResult = selectedIds.count
        } catch {
            AppLog.ui.error("Batch delete failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - §6.1 Export CSV

    /// Builds a simple CSV string from the selected IDs for `.fileExporter`.
    /// Full field data requires a separate fetch — this exports ID list only
    /// (sufficient for import → re-import workflows).
    public var exportCSV: String {
        let header = "inventory_id"
        let rows = selectedIds.map { String($0) }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - §6.8 Mass label print

    /// Items fetched for label rendering; populated by fetchItemsForLabels().
    public private(set) var itemsForLabels: [InventoryListItem] = []

    /// Fetches lightweight item detail (name + SKU) for each selected ID
    /// concurrently, assembling an array suitable for label rendering.
    /// On network failure the array stays empty — the label sheet shows
    /// an empty state instead of crashing.
    public func fetchItemsForLabels() async {
        guard !selectedIds.isEmpty else { return }
        do {
            let items = try await api.inventoryItemsForLabels(ids: selectedIds)
            itemsForLabels = items
        } catch {
            AppLog.ui.debug("Label data fetch failed: \(error.localizedDescription, privacy: .public)")
            itemsForLabels = []
        }
    }

    public func submit() async {
        guard !isSubmitting, hasAnyField, !selectedIds.isEmpty else {
            if !hasAnyField { errorMessage = "Enter at least one update." }
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let updates = BatchInventoryUpdates(
            priceAdjustPercent: parseDouble(priceAdjustPercent),
            category: trimmed(reassignCategory),
            tags: parsedTags
        )
        let req = BatchInventoryRequest(ids: selectedIds, updates: updates)

        do {
            let resp = try await api.batchUpdateInventory(req)
            result = resp.updatedCount
        } catch {
            AppLog.ui.error("Batch inventory update failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private var parsedTags: [String]? {
        let t = newTags.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return t.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func trimmed(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func parseDouble(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Double(t)
    }
}

// MARK: - View

#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers
import DesignSystem

// MARK: - CSV FileDocument (for .fileExporter)

/// Minimal `FileDocument` wrapping CSV text for bulk export.
public struct InventoryCSVDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    public var text: String

    public init(text: String) { self.text = text }

    public init(configuration: ReadConfiguration) throws {
        self.text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// §6.1 — Sheet for batch-editing selected inventory items.
/// Fields: adjust price by %, reassign category, retag, delete, export CSV, print labels.
public struct BatchEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: BatchEditViewModel
    @State private var showDeleteConfirm: Bool = false
    @State private var showExporter: Bool = false
    @State private var showingLabelPrint: Bool = false
    @State private var labelItems: [InventoryListItem] = []

    public init(api: APIClient, selectedIds: [Int64]) {
        _vm = State(wrappedValue: BatchEditViewModel(api: api, selectedIds: selectedIds))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Editing \(vm.selectedIds.count) item\(vm.selectedIds.count == 1 ? "" : "s")")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }

                Section("Price adjustment") {
                    HStack(spacing: BrandSpacing.xs) {
                        TextField("e.g. 10 or -5", text: $vm.priceAdjustPercent)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Price adjustment percentage")
                        Text("%")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                    }
                    Text("Positive = increase, negative = decrease retail price.")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Section("Category") {
                    TextField("New category", text: $vm.reassignCategory)
                        .accessibilityLabel("New category for selected items")
                }

                Section("Tags") {
                    TextField("tag1, tag2, tag3", text: $vm.newTags)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Tags, comma separated")
                    Text("Replaces existing tags on all selected items.")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                    .accessibilityLabel("Error: \(err)")
                }

                if let count = vm.result {
                    Section {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.bizarreSuccess)
                                .accessibilityHidden(true)
                            Text("Updated \(count) item\(count == 1 ? "" : "s").")
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreSuccess)
                        }
                    }
                    .accessibilityLabel("Updated \(count) items successfully")
                }

                if let count = vm.deleteResult {
                    Section {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.bizarreSuccess).accessibilityHidden(true)
                            Text("Deleted \(count) item\(count == 1 ? "" : "s").").font(.brandBodyLarge()).foregroundStyle(.bizarreSuccess)
                        }
                    }
                    .accessibilityLabel("Deleted \(count) items")
                }

                // §6.1/§6.8 Export + Print labels
                Section("Export & Print") {
                    Button {
                        showExporter = true
                    } label: {
                        Label("Export \(vm.selectedIds.count) items as CSV", systemImage: "arrow.down.doc")
                            .foregroundStyle(.bizarreOrange)
                    }
                    .accessibilityLabel("Export selected items as CSV")

                    // §6.8 Mass label print — AirPrint or MFi thermal
                    Button {
                        Task { await vm.fetchItemsForLabels() }
                        showingLabelPrint = true
                    } label: {
                        Label("Print \(vm.selectedIds.count) label\(vm.selectedIds.count == 1 ? "" : "s")", systemImage: "printer")
                            .foregroundStyle(.bizarreOrange)
                    }
                    .accessibilityLabel("Print barcode labels for selected items")
                }

                // §6.1 Bulk delete (destructive)
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete \(vm.selectedIds.count) item\(vm.selectedIds.count == 1 ? "" : "s")", systemImage: "trash")
                    }
                    .disabled(vm.isSubmitting)
                    .accessibilityLabel("Delete \(vm.selectedIds.count) selected items")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Batch Edit")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete \(vm.selectedIds.count) item\(vm.selectedIds.count == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        await vm.bulkDelete()
                        if vm.deleteResult != nil {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .fileExporter(
                isPresented: $showExporter,
                document: InventoryCSVDocument(text: vm.exportCSV),
                contentType: .commaSeparatedText,
                defaultFilename: "inventory-export-\(vm.selectedIds.count)-items.csv"
            ) { result in
                if case .failure(let err) = result {
                    AppLog.ui.error("Inventory CSV export failed: \(err.localizedDescription, privacy: .public)")
                }
            }
            // §6.8 Mass label print sheet
            .sheet(isPresented: $showingLabelPrint) {
                InventoryLabelPrintSheet(items: vm.itemsForLabels)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel batch edit")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Updating…" : "Apply") {
                        Task {
                            await vm.submit()
                            if vm.result != nil {
                                try? await Task.sleep(nanoseconds: 800_000_000)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.hasAnyField || vm.isSubmitting)
                    .accessibilityLabel(vm.isSubmitting ? "Updating items" : "Apply batch edit")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - brandBodySmall (local extension for convenience)

private extension Font {
    static func brandBodySmall() -> Font { .system(size: 13) }
}
#endif
