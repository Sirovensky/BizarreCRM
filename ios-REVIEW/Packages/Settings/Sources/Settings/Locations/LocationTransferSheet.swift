import SwiftUI
import Core
import DesignSystem

// MARK: - §60.2 LocationTransferSheet

/// Initiate a stock transfer between locations.
public struct LocationTransferSheet: View {
    @Environment(\.dismiss) private var dismiss

    let repo: any LocationRepository
    let locations: [Location]
    let onCreated: (LocationTransferRequest) -> Void

    @State private var fromLocationId: String = ""
    @State private var toLocationId: String = ""
    @State private var sku: String = ""
    @State private var itemName: String = ""
    @State private var quantity: Int = 1
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    public init(
        repo: any LocationRepository,
        locations: [Location],
        onCreated: @escaping (LocationTransferRequest) -> Void
    ) {
        self.repo = repo
        self.locations = locations
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    locationPicker(label: "From", selection: $fromLocationId, excluding: toLocationId)
                }

                Section("Destination") {
                    locationPicker(label: "To", selection: $toLocationId, excluding: fromLocationId)
                }

                Section("Item") {
                    TextField("SKU", text: $sku)
                        .font(.brandMono(size: 15))
                        .autocorrectionDisabled()
                        .accessibilityLabel("SKU")
                    TextField("Item name (optional)", text: $itemName)
                        .accessibilityLabel("Item name")
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                        .accessibilityLabel("Quantity \(quantity)")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .navigationTitle("Transfer Stock")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating…" : "Create") {
                        Task { await submit() }
                    }
                    .disabled(isSaving || !isValid)
                    .accessibilityLabel("Create transfer")
                }
            }
            .onAppear {
                if let first = locations.first { fromLocationId = first.id }
                if locations.count > 1 { toLocationId = locations[1].id }
            }
        }
    }

    // MARK: Private

    private var isValid: Bool {
        !fromLocationId.isEmpty
        && !toLocationId.isEmpty
        && fromLocationId != toLocationId
        && !sku.isEmpty
        && quantity > 0
    }

    @ViewBuilder
    private func locationPicker(label: String, selection: Binding<String>, excluding excluded: String) -> some View {
        Picker(label, selection: selection) {
            ForEach(locations.filter { $0.id != excluded && $0.active }) { loc in
                Text(loc.name).tag(loc.id)
            }
        }
        .accessibilityLabel("\(label) location")
    }

    private func submit() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let req = CreateTransferRequest(
                fromLocationId: fromLocationId,
                toLocationId: toLocationId,
                items: [TransferItem(sku: sku, quantity: quantity, name: itemName.isEmpty ? nil : itemName)]
            )
            let transfer = try await repo.createTransfer(req)
            onCreated(transfer)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
