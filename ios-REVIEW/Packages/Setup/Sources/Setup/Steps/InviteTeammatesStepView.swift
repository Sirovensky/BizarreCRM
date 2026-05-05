import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - InvitePayload

public struct InvitePayload: Sendable, Equatable {
    public var email: String
    public var role: TeammateRole
    public var sendSMS: Bool

    public init(email: String, role: TeammateRole, sendSMS: Bool = false) {
        self.email   = email
        self.role    = role
        self.sendSMS = sendSMS
    }
}

public enum TeammateRole: String, CaseIterable, Sendable, Equatable {
    case manager    = "manager"
    case technician = "technician"
    case sales      = "sales"

    public var displayName: String {
        switch self {
        case .manager:    return "Manager"
        case .technician: return "Technician"
        case .sales:      return "Sales"
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class InviteTeammatesViewModel {

    // MARK: State

    var emailsRaw: String = ""
    var defaultRole: TeammateRole = .manager
    var sendSMS: Bool = false

    // MARK: Submission outcome

    var invitesSentCount: Int = 0
    var confirmationMessage: String? = nil

    // MARK: Validation

    var listError: String? = nil

    var parsedInvitees: [InvitePayload] {
        let (_, emails) = Step9Validator.validateEmailList(emailsRaw)
        return emails.enumerated().map { idx, email in
            InvitePayload(
                email: email,
                role: idx == 0 ? .manager : defaultRole,
                sendSMS: sendSMS
            )
        }
    }

    var isNextEnabled: Bool {
        Step9Validator.isNextEnabled(raw: emailsRaw)
    }

    func validateList() {
        let (result, _) = Step9Validator.validateEmailList(emailsRaw)
        listError = result.isValid ? nil : result.errorMessage
    }
}

// MARK: - View  (§36.2 Step 9 — Invite Teammates)

@MainActor
public struct InviteTeammatesStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: ([InvitePayload]) -> Void

    @State private var vm = InviteTeammatesViewModel()
    @FocusState private var emailsFocused: Bool

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping ([InvitePayload]) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                header

                emailsField

                roleSection

                smsToggle

                if let confirmation = vm.confirmationMessage {
                    confirmationBanner(message: confirmation)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { onValidityChanged(vm.isNextEnabled) }
        .onChange(of: vm.isNextEnabled) { _, valid in onValidityChanged(valid) }
        .onChange(of: vm.emailsRaw) { _, _ in
            if !vm.emailsRaw.isEmpty { vm.validateList() }
        }
    }

    // MARK: Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Invite Teammates")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.top, BrandSpacing.lg)
                .accessibilityAddTraits(.isHeader)

            Text("Add team members by email. You can skip this and invite later from Settings.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    private var emailsField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Email Addresses")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            TextEditor(text: $vm.emailsRaw)
                .font(.brandBodyLarge())
                .focused($emailsFocused)
                .frame(minHeight: 100)
                .padding(BrandSpacing.md)
                .background(
                    Color.bizarreSurface1.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            vm.listError != nil ? Color.bizarreError : Color.bizarreOutline.opacity(0.5),
                            lineWidth: 1
                        )
                )
                .onChange(of: emailsFocused) { _, focused in
                    if !focused { vm.validateList() }
                }
                .accessibilityLabel("Email addresses")
                .accessibilityHint("Enter one or more emails, separated by commas or new lines")
            #if canImport(UIKit)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            #endif

            if let err = vm.listError {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreError)
                    .accessibilityLabel("Error: \(err)")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text("Separate multiple emails with commas or new lines")
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
        .animation(.easeInOut(duration: 0.15), value: vm.listError)
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Default Role")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            Picker("Default Role", selection: $vm.defaultRole) {
                ForEach(TeammateRole.allCases, id: \.self) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Default role for invited teammates")

            Text("First invitee gets Manager; the rest get the selected role.")
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    private var smsToggle: some View {
        Toggle(isOn: $vm.sendSMS) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Send SMS invite link")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                Text("Requires SMS setup in the next step")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .toggleStyle(.switch)
        .tint(.bizarreOrange)
        .padding(BrandSpacing.sm)
        .background(
            Color.bizarreSurface1.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityLabel("Send SMS invite link")
        .accessibilityValue(vm.sendSMS ? "On" : "Off")
    }

    private func confirmationBanner(message: String) -> some View {
        Text(message)
            .font(.brandBodyMedium())
            .foregroundStyle(.white)
            .padding(BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreSuccess, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(message)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
