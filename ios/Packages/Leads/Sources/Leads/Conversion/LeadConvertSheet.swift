import SwiftUI
import Networking
import DesignSystem
import Core

// MARK: - LeadConvertSheet

/// §9.4 — "Convert to Customer" bottom sheet.
/// Pre-fills customer info from the lead; optionally creates a linked ticket.
public struct LeadConvertSheet: View {
    @State private var vm: LeadConvertViewModel
    private let lead: LeadDetail
    /// Called with (ticketId, customerId?) after successful conversion.
    private let onSuccess: (Int64, Int64?) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, lead: LeadDetail, onSuccess: @escaping (_ ticketId: Int64, _ customerId: Int64?) -> Void) {
        self.lead = lead
        self.onSuccess = onSuccess
        _vm = State(wrappedValue: LeadConvertViewModel(api: api, leadId: lead.id))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        // Pre-filled customer preview
                        prefillCard
                        // Options
                        ticketToggle
                        // CTA
                        convertButton
                        // Error
                        if case .failed(let msg) = vm.state {
                            Text(msg)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, BrandSpacing.xs)
                        }
                    }
                    .padding(BrandSpacing.base)
                    .frame(maxWidth: 600, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Convert to Customer")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(vm.state.isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: vm.state.isSuccess) { _, isSuccess in
            if isSuccess, case .success(let tId, let cId) = vm.state {
                onSuccess(tId, cId)
                dismiss()
            }
        }
    }

    // MARK: - Sub-views

    private var prefillCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("CUSTOMER DETAILS")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
            infoRow(label: "Name", value: lead.displayName)
            if let phone = lead.phone, !phone.isEmpty {
                infoRow(label: "Phone", value: PhoneFormatter.format(phone))
            }
            if let email = lead.email, !email.isEmpty {
                infoRow(label: "Email", value: email)
            }
            if let source = lead.source, !source.isEmpty {
                infoRow(label: "Source", value: source.capitalized)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var ticketToggle: some View {
        Toggle(isOn: $vm.createTicket) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Create a linked ticket")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Opens a new support ticket for this customer.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .tint(.bizarreOrange)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .disabled(vm.state.isSubmitting)
    }

    private var convertButton: some View {
        Button {
            Task { await vm.convert() }
        } label: {
            Group {
                if vm.state.isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.bizarreOnOrange)
                } else {
                    Text("Convert to Customer")
                        .font(.brandTitleSmall())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(vm.state.isSubmitting)
        .accessibilityLabel("Convert lead to customer")
    }

}

