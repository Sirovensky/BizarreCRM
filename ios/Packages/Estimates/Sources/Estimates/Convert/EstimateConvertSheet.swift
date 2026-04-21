import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateConvertSheet

/// Sheet presenting estimate summary + "Create Ticket" action.
/// Presented from `EstimateDetailView` toolbar "Convert to Ticket".
public struct EstimateConvertSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EstimateConvertViewModel

    public init(
        estimate: Estimate,
        api: APIClient,
        onSuccess: @escaping @MainActor (Int64) -> Void
    ) {
        _vm = State(wrappedValue: EstimateConvertViewModel(
            estimate: estimate,
            api: api,
            onSuccess: onSuccess
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        summaryCard
                        if let err = vm.errorMessage {
                            errorBanner(err)
                        }
                        convertButton
                    }
                    .padding(BrandSpacing.lg)
                }
            }
            .navigationTitle("Convert to Ticket")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel convert")
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: vm.createdTicketId) { _, id in
            if id != nil { dismiss() }
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Label("Estimate Summary", systemImage: "doc.text")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Divider()

            summaryRow(label: "Estimate #", value: vm.orderId)
            summaryRow(label: "Customer", value: vm.customerName)
            summaryRow(label: "Total", value: vm.totalFormatted)
            if let status = vm.estimate.status, !status.isEmpty {
                summaryRow(label: "Status", value: status.capitalized)
            }
            if let until = vm.estimate.validUntil, !until.isEmpty {
                summaryRow(label: "Valid until", value: String(until.prefix(10)))
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Convert button

    private var convertButton: some View {
        Button {
            Task { await vm.convert() }
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                if vm.isConverting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .accessibilityHidden(true)
                }
                Text(vm.isConverting ? "Creating ticket…" : "Create Ticket")
                    .font(.brandTitleMedium())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(vm.isConverting)
        .accessibilityLabel(vm.isConverting ? "Creating ticket, please wait" : "Create Ticket from estimate")
        .accessibilityHint("Converts this estimate into a new service ticket")
    }
}
