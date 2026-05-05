#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - InvoiceConvertFromEstimateSheet
//
// §7.3: Convert from estimate — prefill line items via POST /estimates/:id/convert-to-invoice.
//
// The server converts the estimate to a new draft invoice and returns the invoice id.
// We present a success card + "Open Invoice" CTA.

@Observable
@MainActor
final class InvoiceConvertFromEstimateViewModel {
    var estimateId: String = ""
    var isConverting = false
    var errorMessage: String?
    var convertedInvoiceId: Int64?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var canConvert: Bool {
        Int64(estimateId.trimmingCharacters(in: .whitespaces)) != nil
    }

    func convert() async {
        guard let id = Int64(estimateId.trimmingCharacters(in: .whitespaces)) else { return }
        isConverting = true
        errorMessage = nil
        do {
            let response = try await api.convertEstimateToInvoice(estimateId: id)
            convertedInvoiceId = response.invoiceId
        } catch {
            errorMessage = error.localizedDescription
        }
        isConverting = false
    }
}

public struct InvoiceConvertFromEstimateSheet: View {
    @State private var vm: InvoiceConvertFromEstimateViewModel
    private let onOpenInvoice: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, onOpenInvoice: @escaping (Int64) -> Void) {
        _vm = State(wrappedValue: InvoiceConvertFromEstimateViewModel(api: api))
        self.onOpenInvoice = onOpenInvoice
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    if let invoiceId = vm.convertedInvoiceId {
                        successSection(invoiceId: invoiceId)
                    } else {
                        convertSection
                    }
                }
            }
            .navigationTitle("Convert from Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var convertSection: some View {
        Section {
            HStack {
                Label("Estimate ID", systemImage: "doc.badge.plus")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("e.g. 205", text: $vm.estimateId)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.brandMono(size: 15))
                    .accessibilityLabel("Estimate ID number")
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Error: \(err)")
            }

            Button {
                Task { await vm.convert() }
            } label: {
                if vm.isConverting {
                    HStack {
                        ProgressView().padding(.trailing, BrandSpacing.xs)
                        Text("Converting…")
                    }
                } else {
                    Label("Convert Estimate to Invoice", systemImage: "arrow.right.doc.on.clipboard")
                        .bold()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(!vm.canConvert || vm.isConverting)
            .foregroundStyle(vm.canConvert ? .bizarreOrange : .bizarreOnSurfaceMuted)
            .accessibilityLabel(vm.isConverting ? "Converting estimate to invoice" : "Convert estimate to invoice")
        } header: {
            Text("Enter the estimate ID to prefill line items from that approved estimate into a new invoice.")
                .font(.brandLabelSmall())
                .textCase(nil)
        }
    }

    private func successSection(invoiceId: Int64) -> some View {
        Section {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text("Invoice created")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Estimate line items have been copied to invoice #\(invoiceId).")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button {
                    onOpenInvoice(invoiceId)
                    dismiss()
                } label: {
                    Label("Open Invoice", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Open invoice \(invoiceId)")
            }
            .padding(.vertical, BrandSpacing.base)
            .frame(maxWidth: .infinity)
        }
    }
}
#endif
