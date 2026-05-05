#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.12 Serial Sell Sheet

/// At POS, when SKU is serial-tracked, prompt staff to scan/select specific unit.
public struct SerialSellSheet: View {
    @State private var vm: SerialSellViewModel
    @Environment(\.dismiss) private var dismiss

    let onConfirm: (SerializedItem) -> Void

    public init(parentSKU: String, api: APIClient, onConfirm: @escaping (SerializedItem) -> Void) {
        _vm = State(wrappedValue: SerialSellViewModel(parentSKU: parentSKU, api: api))
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    scanSection
                    availableList
                }
                .padding(.top, BrandSpacing.md)
            }
            .navigationTitle("Select Unit to Sell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await vm.load() }
        }
        .presentationDetents([.medium, .large])
        .brandGlass()
    }

    // MARK: Scan

    private var scanSection: some View {
        HStack {
            TextField("Scan serial / IMEI", text: $vm.scanInput)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .font(.brandMono(size: 15))
                .submitLabel(.search)
                .onSubmit { Task { await vm.scanSerial() } }
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))

            Button {
                Task { await vm.scanSerial() }
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.title2)
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Scan serial number")
        }
        .padding(.horizontal, BrandSpacing.md)
    }

    // MARK: Available list

    @ViewBuilder
    private var availableList: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.availableUnits.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "xmark.bin.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("No available units for this SKU.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(vm.availableUnits) { item in
                Button {
                    onConfirm(item)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.serialNumber)
                                .font(.brandMono(size: 14))
                                .foregroundStyle(.bizarreOnSurface)
                            Text("Received \(item.receivedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.bizarreOrange)
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityLabel("Select unit \(item.serialNumber), received \(item.receivedAt.formatted(date: .abbreviated, time: .omitted))")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        if let err = vm.errorMessage {
            Text(err)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .padding(.horizontal, BrandSpacing.md)
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class SerialSellViewModel {
    let parentSKU: String
    var availableUnits: [SerializedItem] = []
    var scanInput: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    init(parentSKU: String, api: APIClient) {
        self.parentSKU = parentSKU
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await api.listSerials(parentSKU: parentSKU)
            availableUnits = SerialStatusCalculator.availableUnits(from: all, sku: parentSKU)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scanSerial() async {
        let sn = scanInput.trimmingCharacters(in: .whitespaces)
        guard !sn.isEmpty else { return }
        errorMessage = nil
        do {
            let item = try await api.getSerial(serialNumber: sn)
            guard item.status == .available else {
                errorMessage = "Unit \(sn) is \(item.status.displayName) — cannot sell."
                return
            }
            availableUnits = [item]
        } catch {
            errorMessage = "Serial not found: \(error.localizedDescription)"
        }
    }
}
#endif
