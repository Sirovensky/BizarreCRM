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
                if Platform.isCompact {
                    phoneLayout
                } else {
                    padLayout
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
                        .accessibilityLabel("Cancel convert")
                }
                #if canImport(UIKit)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Convert") { Task { await vm.convert() } }
                        .disabled(vm.state.isSubmitting)
                        .accessibilityLabel("Confirm convert to customer")
                }
                #endif
            }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.large])
        .onChange(of: vm.state.isSuccess) { _, isSuccess in
            if isSuccess, case .success(let tId, let cId) = vm.state {
                onSuccess(tId, cId)
                dismiss()
            }
        }
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                prefillCard
                ticketToggle
                convertButton
                errorBanner
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        HStack(spacing: 0) {
            // Left: customer preview + CTA
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    prefillCard
                    convertButton
                    errorBanner
                }
                .padding(BrandSpacing.lg)
                .frame(maxWidth: 460, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Right: options + informational blurb
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    ticketToggle
                    conversionInfoCard
                }
                .padding(BrandSpacing.lg)
            }
            .frame(maxWidth: 300)
        }
    }

    /// iPad-only: short informational card explaining what conversion does.
    private var conversionInfoCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("What happens?", systemImage: "info.circle")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
            Text("A Customer record is created from this lead's contact details. The lead's pipeline status is set to **Converted** and a new support ticket is opened automatically.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if case .failed(let msg) = vm.state {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { vm.reset() } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Dismiss error")
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreError.opacity(0.3), lineWidth: 0.5)
            )
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

