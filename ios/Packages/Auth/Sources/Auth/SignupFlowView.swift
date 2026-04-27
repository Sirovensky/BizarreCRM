#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §2.7 SignupFlowViewModel

/// Multi-step signup / tenant creation flow.
///
/// Steps: Company → Owner → Server URL (self-hosted) → Confirm.
@MainActor
@Observable
public final class SignupFlowViewModel {

    public enum Step: Int, CaseIterable, Sendable {
        case company = 0
        case owner   = 1
        case server  = 2
        case confirm = 3
    }

    // MARK: - State

    public var step: Step = .company
    public var isSubmitting: Bool = false
    public var errorMessage: String? = nil
    public var isComplete: Bool = false

    // Company step
    public var storeName: String = ""
    public var storePhone: String = ""
    public var storeAddress: String = ""
    public var selectedShopType: ShopType = .repair
    /// Pre-selected from device timezone; user-confirmable.
    public var timezone: String = TimeZone.current.identifier

    // Owner step
    public var firstName: String = ""
    public var lastName: String = ""
    public var email: String = ""
    public var username: String = ""
    public var password: String = ""
    public var confirmPassword: String = ""

    // Server URL step
    public var setupToken: String? = nil // from Universal Link
    public var isSelfHosted: Bool = false
    public var serverURL: String = ""

    // MARK: - Dependencies

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient, setupToken: String? = nil) {
        self.api = api
        self.setupToken = setupToken
    }

    // MARK: - Navigation

    public var canGoNext: Bool {
        switch step {
        case .company: return !storeName.isEmpty
        case .owner:   return !firstName.isEmpty && !email.isEmpty && !username.isEmpty && password.count >= 8 && password == confirmPassword
        case .server:  return !isSelfHosted || !serverURL.isEmpty
        case .confirm: return !isSubmitting
        }
    }

    public func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            Task { await submit() }
            return
        }
        withAnimation(.smooth(duration: 0.25)) { step = next }
    }

    public func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.smooth(duration: 0.25)) { step = prev }
    }

    public var isLastStep: Bool { step == .confirm }
    public var isFirstStep: Bool { step == .company }

    // MARK: - Submit

    public func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let req = SignupRequest(
            username: username,
            password: password,
            email: email.isEmpty ? nil : email,
            firstName: firstName.isEmpty ? nil : firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            storeName: storeName.isEmpty ? nil : storeName,
            shopType: selectedShopType,
            timezone: timezone,
            setupToken: setupToken
        )

        do {
            _ = try await api.signup(request: req)
            isComplete = true
        } catch APITransportError.httpStatus(let code, let msg) {
            switch code {
            case 409:
                errorMessage = "This username or email is already taken. Choose another."
            case 429:
                errorMessage = "Too many signup attempts. Try again in an hour."
            default:
                errorMessage = msg ?? "Signup failed. Check your details and try again."
            }
        } catch {
            errorMessage = "Couldn't reach the server. Check your connection and try again."
        }
    }
}

// MARK: - §2.7 SignupFlowView

/// Multi-step glass panel for new tenant creation.
///
/// - iPhone: full-screen modal.
/// - iPad: centred glass card (max-width 480 pt).
public struct SignupFlowView: View {

    @State private var vm: SignupFlowViewModel
    private let onComplete: (String) -> Void   // passes username back to login
    private let onCancel: () -> Void

    public init(
        viewModel: SignupFlowViewModel,
        onComplete: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._vm = State(wrappedValue: viewModel)
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(SignupFlowViewModel.Step.allCases, id: \.rawValue) { s in
                        Capsule()
                            .fill(s.rawValue <= vm.step.rawValue ? Color.bizarreOrange : Color.bizarreOnSurface.opacity(0.2))
                            .frame(height: 3)
                            .animation(.smooth(duration: 0.25), value: vm.step)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.lg)
                .accessibilityHidden(true)

                ScrollView {
                    VStack(spacing: BrandSpacing.xl) {
                        stepContent
                            .animation(.smooth(duration: 0.25), value: vm.step)

                        if let err = vm.errorMessage {
                            errorCard(err)
                        }

                        navButtons
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.lg)
                    .padding(.bottom, BrandSpacing.xxl)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: vm.isComplete) { _, complete in
            if complete { onComplete(vm.username) }
        }
        .navigationTitle(stepTitle)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
    }

    // MARK: - Step content switch

    @ViewBuilder
    private var stepContent: some View {
        switch vm.step {
        case .company:  companyStep
        case .owner:    ownerStep
        case .server:   serverStep
        case .confirm:  confirmStep
        }
    }

    private var stepTitle: String {
        switch vm.step {
        case .company:  return "Your business"
        case .owner:    return "Your account"
        case .server:   return "Server"
        case .confirm:  return "Confirm"
        }
    }

    // MARK: - Company step

    private var companyStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            sectionHeader(icon: "storefront", title: "Business info", subtitle: "Tell us about your shop.")

            BrandTextField(
                label: "Shop name",
                text: $vm.storeName,
                placeholder: "Main Street Repair",
                systemImage: "signpost.right"
            )

            BrandTextField(
                label: "Phone (optional)",
                text: $vm.storePhone,
                placeholder: "555-123-4567",
                systemImage: "phone",
                contentType: .telephoneNumber,
                keyboard: .phonePad
            )

            // Shop type picker
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Shop type")
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurface)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BrandSpacing.sm) {
                    ForEach(ShopType.allCases, id: \.self) { type in
                        shopTypeCard(type)
                    }
                }
            }

            // Timezone
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Timezone: \(vm.timezone.replacingOccurrences(of: "_", with: " "))")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                Spacer()
            }
        }
    }

    private func shopTypeCard(_ type: ShopType) -> some View {
        let isSelected = vm.selectedShopType == type
        return Button {
            vm.selectedShopType = type
        } label: {
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: type.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                Text(type.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurface)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .brandGlass(
                .regular,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md),
                tint: isSelected ? Color.bizarreOrange.opacity(0.12) : .clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(isSelected ? Color.bizarreOrange.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Owner step

    private var ownerStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            sectionHeader(icon: "person.crop.circle", title: "Your account", subtitle: "Create the owner login.")

            HStack(spacing: BrandSpacing.sm) {
                BrandTextField(label: "First name", text: $vm.firstName, placeholder: "Jane", systemImage: "person")
                BrandTextField(label: "Last name", text: $vm.lastName, placeholder: "Smith", systemImage: "person")
            }

            BrandTextField(
                label: "Email",
                text: $vm.email,
                placeholder: "jane@example.com",
                systemImage: "envelope",
                contentType: .emailAddress,
                keyboard: .emailAddress,
                autocapitalize: .never,
                autocorrect: false
            )

            BrandTextField(
                label: "Username",
                text: $vm.username,
                placeholder: "janesmith",
                systemImage: "person.badge.key",
                contentType: .username,
                autocapitalize: .never,
                autocorrect: false
            )

            BrandSecureField(
                label: "Password",
                text: $vm.password,
                placeholder: "At least 8 characters",
                systemImage: "lock"
            )
            .privacySensitive()

            BrandSecureField(
                label: "Confirm password",
                text: $vm.confirmPassword,
                placeholder: "Type it again",
                systemImage: "lock.fill"
            )
            .privacySensitive()

            if !vm.confirmPassword.isEmpty && vm.password != vm.confirmPassword {
                Label("Passwords don't match.", systemImage: "exclamationmark.circle.fill")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreError)
            }
        }
    }

    // MARK: - Server step

    private var serverStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            sectionHeader(icon: "server.rack", title: "Server", subtitle: "Where will your data live?")

            Toggle(isOn: $vm.isSelfHosted) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Self-hosted server")
                        .font(.brandBodyLarge())
                        .foregroundStyle(Color.bizarreOnSurface)
                    Text("You run your own server at a custom URL.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
            }
            .tint(Color.bizarreOrange)

            if vm.isSelfHosted {
                BrandTextField(
                    label: "Server URL",
                    text: $vm.serverURL,
                    placeholder: "https://myserver.example.com",
                    systemImage: "globe",
                    contentType: .URL,
                    keyboard: .URL,
                    autocapitalize: .never,
                    autocorrect: false
                )
            } else {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.bizarreSuccess)
                    Text("Bizarre CRM Cloud (managed)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(Color.bizarreOnSurface)
                }
                .padding(BrandSpacing.md)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
        }
    }

    // MARK: - Confirm step

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            sectionHeader(icon: "checkmark.seal", title: "Ready to go", subtitle: "Review and create your account.")

            // Summary card
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                summaryRow(icon: "storefront", label: "Shop", value: vm.storeName)
                summaryRow(icon: vm.selectedShopType.icon, label: "Type", value: vm.selectedShopType.displayName)
                summaryRow(icon: "person", label: "Owner", value: "\(vm.firstName) \(vm.lastName)".trimmingCharacters(in: .whitespaces))
                summaryRow(icon: "envelope", label: "Email", value: vm.email)
                summaryRow(icon: "person.badge.key", label: "Username", value: vm.username)
                summaryRow(icon: "globe", label: "Timezone", value: vm.timezone.replacingOccurrences(of: "_", with: " "))
            }
            .padding(BrandSpacing.md)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

            Text("By creating an account you agree to the BizarreCRM Terms of Service and Privacy Policy.")
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.leading)
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .frame(width: 72, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .lineLimit(1)
            Spacer()
        }
    }

    // MARK: - Error card

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md), tint: Color.bizarreError.opacity(0.10))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Navigation buttons

    private var navButtons: some View {
        HStack(spacing: BrandSpacing.md) {
            if !vm.isFirstStep {
                Button {
                    vm.goBack()
                } label: {
                    Text("Back")
                        .font(.brandLabelLarge())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            Button {
                if vm.isLastStep {
                    Task { await vm.submit() }
                } else {
                    vm.goNext()
                }
            } label: {
                ZStack {
                    if vm.isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.bizarreOnSurface)
                    } else {
                        Text(vm.isLastStep ? "Create account" : "Next")
                            .font(.brandLabelLarge().bold())
                            .foregroundStyle(Color.bizarreOnSurface)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.brandGlassProminent)
            .disabled(!vm.canGoNext || vm.isSubmitting)
            .accessibilityLabel(vm.isLastStep ? "Create account" : "Next step")
        }
    }

    // MARK: - Section header

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.brandDisplaySmall())
                    .foregroundStyle(Color.bizarreOnSurface)
            }
            Text(subtitle)
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }
}

#endif
