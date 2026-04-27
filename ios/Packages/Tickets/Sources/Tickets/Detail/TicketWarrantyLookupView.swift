#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.5 — Warranty lookup quick action.
// Searches GET /api/v1/tickets/warranty-lookup by IMEI, serial, or phone.
// Presented as a sheet from ticket detail "Check warranty" quick action.

@MainActor
@Observable
final class TicketWarrantyLookupViewModel {
    var imei: String = ""
    var serial: String = ""
    var phone: String = ""

    enum State { case idle, loading, found(TicketWarrantyRecord), notFound, error(String) }
    var state: State = .idle

    private let api: APIClient

    init(api: APIClient, prefillImei: String? = nil, prefillSerial: String? = nil) {
        self.api = api
        self.imei = prefillImei ?? ""
        self.serial = prefillSerial ?? ""
    }

    func lookup() async {
        guard !imei.isEmpty || !serial.isEmpty || !phone.isEmpty else { return }
        state = .loading
        do {
            if let record = try await api.warrantyLookup(imei: imei.isEmpty ? nil : imei,
                                                         serial: serial.isEmpty ? nil : serial,
                                                         phone: phone.isEmpty ? nil : phone) {
                state = .found(record)
            } else {
                state = .notFound
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

public struct TicketWarrantyLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketWarrantyLookupViewModel

    public init(api: APIClient, prefillImei: String? = nil, prefillSerial: String? = nil) {
        _vm = State(wrappedValue: TicketWarrantyLookupViewModel(api: api, prefillImei: prefillImei, prefillSerial: prefillSerial))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.lg) {
                        searchForm
                        resultView
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Warranty Lookup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close warranty lookup")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search form

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Enter at least one identifier to search.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            TextField("IMEI", text: $vm.imei)
                .keyboardType(.numberPad)
                .autocorrectionDisabled()
                .textContentType(.none)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityLabel("IMEI number")

            TextField("Serial number", text: $vm.serial)
                .autocorrectionDisabled()
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityLabel("Serial number")

            TextField("Customer phone", text: $vm.phone)
                .keyboardType(.phonePad)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityLabel("Customer phone number")

            Button {
                Task { await vm.lookup() }
            } label: {
                HStack {
                    Spacer()
                    if case .loading = vm.state {
                        ProgressView().tint(.white)
                    } else {
                        Label("Check Warranty", systemImage: "magnifyingglass")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                .padding(.vertical, BrandSpacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(vm.imei.isEmpty && vm.serial.isEmpty && vm.phone.isEmpty)
            .accessibilityLabel("Check warranty")
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultView: some View {
        switch vm.state {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Looking up warranty…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.xl)
        case .notFound:
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "shield.slash")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No warranty found.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.xl)
        case .found(let record):
            warrantyCard(record)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.bizarreError)
                .font(.brandBodyMedium())
                .padding(BrandSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityLabel("Error: \(msg)")
        }
    }

    private func warrantyCard(_ record: TicketWarrantyRecord) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: record.isEligible == true ? "checkmark.shield.fill" : "shield.slash")
                    .foregroundStyle(record.isEligible == true ? .bizarreSuccess : .bizarreError)
                    .font(.system(size: 22, weight: .semibold))
                    .accessibilityHidden(true)
                Text(record.isEligible == true ? "Under Warranty" : "Warranty Expired")
                    .font(.brandTitleMedium())
                    .foregroundStyle(record.isEligible == true ? .bizarreSuccess : .bizarreError)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(record.isEligible == true ? "Under warranty" : "Warranty expired")

            Divider()

            if let part = record.partName {
                rowLabel("Part / Service", value: part)
            }
            if let install = record.installDate {
                rowLabel("Install date", value: install)
            }
            if let expires = record.expiresAt {
                rowLabel("Expires", value: expires)
            }
            if let days = record.durationDays {
                rowLabel("Duration", value: "\(days) days")
            }
            if let notes = record.notes, !notes.isEmpty {
                rowLabel("Notes", value: notes)
            }
            if let orderId = record.orderId {
                rowLabel("Original ticket", value: orderId)
                    .textSelection(.enabled)
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func rowLabel(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
#endif
