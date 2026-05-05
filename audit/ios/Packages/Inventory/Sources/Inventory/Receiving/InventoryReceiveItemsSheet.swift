#if canImport(UIKit)
import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §6.1 Receive items modal
// Allows operator to scan items into stock manually or add by SKU lookup.
// Creates a stock-movement batch via POST /api/v1/inventory/receive-scan.

@MainActor
@Observable
final class ReceiveItemsViewModel {
    var lines: [ReceiveLine] = []
    var isSubmitting: Bool = false
    var errorMessage: String?
    var successMessage: String?

    struct ReceiveLine: Identifiable {
        let id = UUID()
        var sku: String
        var name: String
        var qty: Int
    }

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    func addLine(sku: String, name: String, qty: Int = 1) {
        // Merge if same SKU
        if let idx = lines.firstIndex(where: { $0.sku == sku }) {
            lines[idx].qty += qty
        } else {
            lines.append(ReceiveLine(sku: sku, name: name, qty: qty))
        }
    }

    func removeLine(id: UUID) {
        lines.removeAll { $0.id == id }
    }

    func submit() async {
        guard !lines.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let entries = lines.map { ScanReceiveEntry(barcode: $0.sku, quantity: $0.qty) }
            let req = ScanReceiveRequest(items: entries)
            try await api.scanReceive(req)
            successMessage = "Received \(lines.count) line(s) into stock."
        } catch {
            AppLog.ui.error("ReceiveItems submit failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Sheet

public struct InventoryReceiveItemsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ReceiveItemsViewModel
    @State private var showingScanner: Bool = false
    @State private var manualSKU: String = ""
    @State private var manualName: String = ""
    @State private var manualQty: Int = 1

    public init(api: APIClient) {
        _vm = State(wrappedValue: ReceiveItemsViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    // Quick-add by scan or manual
                    Section("Add item") {
                        TextField("SKU or barcode", text: $manualSKU)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Enter SKU or barcode")
                        TextField("Item name (optional)", text: $manualName)
                            .accessibilityLabel("Item name")
                        Stepper("Qty: \(manualQty)", value: $manualQty, in: 1...9999)
                            .accessibilityLabel("Quantity: \(manualQty)")
                        HStack {
                            Button("Add line") {
                                guard !manualSKU.isEmpty else { return }
                                vm.addLine(sku: manualSKU, name: manualName.isEmpty ? manualSKU : manualName, qty: manualQty)
                                manualSKU = ""
                                manualName = ""
                                manualQty = 1
                                BrandHaptics.tap()
                            }
                            .disabled(manualSKU.isEmpty)
                            .accessibilityLabel("Add item line")

                            Spacer()

                            Button {
                                showingScanner = true
                            } label: {
                                Label("Scan", systemImage: "barcode.viewfinder")
                                    .font(.brandBodyMedium())
                            }
                            .accessibilityLabel("Open barcode scanner to receive item")
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    if !vm.lines.isEmpty {
                        Section("Lines to receive (\(vm.lines.count))") {
                            ForEach(vm.lines) { line in
                                HStack {
                                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                        Text(line.name)
                                            .font(.brandBodyLarge())
                                            .foregroundStyle(.bizarreOnSurface)
                                        Text(line.sku)
                                            .font(.brandMono(size: 13))
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                    Text("×\(line.qty)")
                                        .font(.brandTitleMedium())
                                        .monospacedDigit()
                                        .foregroundStyle(.bizarreOrange)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(line.name), SKU \(line.sku), quantity \(line.qty)")
                            }
                            .onDelete { indices in
                                indices.forEach { i in vm.removeLine(id: vm.lines[i].id) }
                            }
                        }
                        .listRowBackground(Color.bizarreSurface1)
                    }

                    if let err = vm.errorMessage {
                        Section {
                            Text(err)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreError)
                        }
                        .listRowBackground(Color.bizarreSurface1)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Receive Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel receiving")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await vm.submit()
                            if vm.successMessage != nil { dismiss() }
                        }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView().tint(.bizarreOrange)
                        } else {
                            Text("Receive All")
                        }
                    }
                    .disabled(vm.lines.isEmpty || vm.isSubmitting)
                    .accessibilityLabel("Receive all lines into stock")
                }
            }
            .sheet(isPresented: $showingScanner) {
                InventoryBarcodeScanSheet { code in
                    vm.addLine(sku: code, name: code, qty: 1)
                    BrandHaptics.success()
                    showingScanner = false
                }
            }
        }
    }
}

#endif
