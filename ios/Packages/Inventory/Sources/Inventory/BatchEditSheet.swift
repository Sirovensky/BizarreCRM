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
import DesignSystem

/// §6.7 — Sheet for batch-editing selected inventory items.
/// Fields: adjust price by %, reassign category, retag.
public struct BatchEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: BatchEditViewModel

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
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Batch Edit")
            .navigationBarTitleDisplayMode(.inline)
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
