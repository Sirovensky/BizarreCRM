#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.12 Serial Receive Sheet

/// At receiving time, scan each unit's serial number individually (vs. bulk qty entry).
public struct SerialReceiveSheet: View {
    @State private var vm: SerialReceiveViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(parentSKU: String, expectedQty: Int, locationId: Int64?, api: APIClient) {
        _vm = State(wrappedValue: SerialReceiveViewModel(
            parentSKU: parentSKU,
            expectedQty: expectedQty,
            locationId: locationId,
            api: api
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    progressHeader
                    scanContent
                }
            }
            .navigationTitle("Receive Serials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.bizarreOrange)
                        .disabled(vm.scannedItems.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .brandGlass()
    }

    // MARK: Progress header

    private var progressHeader: some View {
        HStack {
            Text("Scanned: \(vm.scannedItems.count) / \(vm.expectedQty)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            ProgressView(value: Double(vm.scannedItems.count), total: Double(max(vm.expectedQty, 1)))
                .progressViewStyle(.linear)
                .tint(.bizarreOrange)
                .frame(width: 100)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1)
        .accessibilityLabel("Scanned \(vm.scannedItems.count) of \(vm.expectedQty) units")
    }

    // MARK: Scan content

    private var scanContent: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.md) {
                serialInputRow
                if let err = vm.errorMessage {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BrandSpacing.md)
                }
                scannedList
            }
            .padding(.vertical, BrandSpacing.md)
        }
    }

    private var serialInputRow: some View {
        HStack {
            TextField("Scan IMEI / Serial", text: $vm.currentInput)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .font(.brandMono(size: 15))
                .submitLabel(.done)
                .onSubmit { Task { await vm.addSerial() } }
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))

            if vm.isSubmitting {
                ProgressView().scaleEffect(0.85)
            } else {
                Button {
                    Task { await vm.addSerial() }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.bizarreOrange)
                }
                .disabled(vm.currentInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add serial number")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
    }

    private var scannedList: some View {
        LazyVStack(spacing: BrandSpacing.xs) {
            ForEach(vm.scannedItems) { item in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.bizarreSuccess)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.serialNumber)
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurface)
                            .textSelection(.enabled)
                        Text("Received")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                }
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, BrandSpacing.md)
                .accessibilityLabel("Serial \(item.serialNumber) received")
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class SerialReceiveViewModel {
    let parentSKU: String
    let expectedQty: Int
    let locationId: Int64?
    var currentInput: String = ""
    var scannedItems: [SerializedItem] = []
    var isSubmitting: Bool = false
    var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    init(parentSKU: String, expectedQty: Int, locationId: Int64?, api: APIClient) {
        self.parentSKU = parentSKU
        self.expectedQty = expectedQty
        self.locationId = locationId
        self.api = api
    }

    func addSerial() async {
        let sn = currentInput.trimmingCharacters(in: .whitespaces)
        guard !sn.isEmpty else { return }
        if let err = IMEIValidator.validate(sn) {
            errorMessage = err
            return
        }
        if scannedItems.contains(where: { $0.serialNumber == sn }) {
            errorMessage = "Serial \(sn) already scanned."
            return
        }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let item = try await api.createSerial(
                CreateSerialRequest(parentSKU: parentSKU, serialNumber: sn, locationId: locationId)
            )
            scannedItems.append(item)
            currentInput = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
