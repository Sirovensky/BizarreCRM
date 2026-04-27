#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5 Ticket intake quick-prompt: "How'd you like updates?"
//
// Shown during ticket create when a customer record doesn't yet have
// confirmed communication preferences.
// Staff set SMS/email toggles; saved via PATCH /customers/:id/comm-prefs.

public struct TicketIntakeUpdatePromptView: View {
    let customerId: Int64
    let customerName: String
    let api: APIClient
    var onSaved: (() -> Void)?

    @State private var smsEnabled = false
    @State private var emailEnabled = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isDismissed = false

    public init(
        customerId: Int64,
        customerName: String,
        api: APIClient,
        onSaved: (() -> Void)? = nil
    ) {
        self.customerId = customerId
        self.customerName = customerName
        self.api = api
        self.onSaved = onSaved
    }

    public var body: some View {
        if isDismissed { return AnyView(EmptyView()) }
        return AnyView(promptCard)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Ticket Updates")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss update preference prompt")
            }

            Text("How would \(customerName) like to receive ticket updates?")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            HStack(spacing: BrandSpacing.sm) {
                channelToggle(
                    label: "SMS",
                    icon: "message.fill",
                    isOn: $smsEnabled,
                    color: .bizarreOrange
                )
                channelToggle(
                    label: "Email",
                    icon: "envelope.fill",
                    isOn: $emailEnabled,
                    color: .bizarreTeal
                )
            }

            if let err = errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }

            HStack(spacing: BrandSpacing.sm) {
                Button {
                    isDismissed = true
                } label: {
                    Text("Skip")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOnSurfaceMuted)

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(isSaving)
            }
        }
        .padding(BrandSpacing.base)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOrange.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func channelToggle(
        label: String,
        icon: String,
        isOn: Binding<Bool>,
        color: Color
    ) -> some View {
        Button {
            withAnimation(.snappy) { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandLabelLarge().weight(.semibold))
            }
            .foregroundStyle(isOn.wrappedValue ? .white : color)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isOn.wrappedValue ? color : color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color.opacity(isOn.wrappedValue ? 0 : 0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) updates: \(isOn.wrappedValue ? "on" : "off"). Tap to toggle.")
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await api.setCustomerUpdatePrefs(
                customerId: customerId,
                sms: smsEnabled,
                email: emailEnabled
            )
            onSaved?()
            isDismissed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `PATCH /api/v1/customers/:id/comm-prefs` — update ticket update channel prefs.
    public func setCustomerUpdatePrefs(
        customerId: Int64, sms: Bool, email: Bool
    ) async throws {
        struct Body: Encodable {
            let sms_updates_enabled: Bool
            let email_updates_enabled: Bool
        }
        try await patch(
            "/api/v1/customers/\(customerId)/comm-prefs",
            body: Body(sms_updates_enabled: sms, email_updates_enabled: email)
        )
    }
}

#endif
