import SwiftUI
import Core
import DesignSystem
import Networking

public struct LoginFlowView: View {
    @State private var flow: LoginFlow

    public init(flow: LoginFlow? = nil) {
        let apiClient: APIClient = APIClientImpl(config: .fromBundle())
        self._flow = State(wrappedValue: flow ?? LoginFlow(api: apiClient))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    header
                    WaveDivider()
                        .padding(.horizontal, BrandSpacing.lg)
                    stepContent
                        .padding(BrandSpacing.lg)
                        .frame(maxWidth: 480)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(Color.bizarreOutline, lineWidth: 1)
                        )
                }
                .padding(.top, BrandSpacing.xxl)
                .padding(.horizontal, BrandSpacing.base)
            }
        }
    }

    private var header: some View {
        VStack(spacing: BrandSpacing.xs) {
            Text("Bizarre CRM")
                .font(.brandDisplayMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(subtitleForStep)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var subtitleForStep: String {
        switch flow.step {
        case .credentials:       return "Sign in to your shop."
        case .twoFactor:         return "Enter your 6-digit code."
        case .pinSetup:          return "Create a 4–6 digit PIN."
        case .pinVerify:         return "Enter your PIN."
        case .biometricOffer:    return "Enable biometric unlock?"
        case .done:              return "Signed in."
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .credentials:        credentialsForm
        case .twoFactor:          twoFactorForm
        case .pinSetup:           pinSetupForm
        case .pinVerify:          pinVerifyForm
        case .biometricOffer:     biometricOffer
        case .done:               doneView
        }
    }

    private var credentialsForm: some View {
        VStack(spacing: BrandSpacing.md) {
            TextField("Email", text: $flow.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))

            SecureField("Password", text: $flow.password)
                .textContentType(.password)
                .submitLabel(.go)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))

            if let err = flow.errorMessage {
                Text(err)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await flow.submitCredentials() }
            } label: {
                HStack {
                    if flow.isSubmitting { ProgressView().tint(.black) }
                    Text("Sign in").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(flow.isSubmitting || flow.email.isEmpty || flow.password.isEmpty)
        }
    }

    private var twoFactorForm: some View {
        VStack(spacing: BrandSpacing.md) {
            SecureField("123 456", text: $flow.totpCode)
                .font(.brandMono(size: 22))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .kerning(8)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))

            if let err = flow.errorMessage {
                Text(err).foregroundStyle(.bizarreError)
            }

            Button("Verify") {
                Task { await flow.submit2FA() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(flow.totpCode.count != 6)
        }
    }

    private var pinSetupForm: some View {
        VStack(spacing: BrandSpacing.md) {
            SecureField("PIN", text: $flow.pin)
                .keyboardType(.numberPad)
            SecureField("Confirm PIN", text: $flow.confirmPin)
                .keyboardType(.numberPad)
            if let err = flow.errorMessage {
                Text(err).foregroundStyle(.bizarreError)
            }
            Button("Save PIN") { flow.enrollPIN() }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
    }

    private var pinVerifyForm: some View {
        VStack(spacing: BrandSpacing.md) {
            SecureField("PIN", text: $flow.pin)
                .keyboardType(.numberPad)
            if let err = flow.errorMessage {
                Text(err).foregroundStyle(.bizarreError)
            }
            Button("Unlock") { _ = flow.verifyPIN() }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
    }

    private var biometricOffer: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "faceid")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOrange)
            Text("Unlock Bizarre CRM quickly with Face ID or Touch ID.")
                .multilineTextAlignment(.center)

            Button("Enable") {
                Task {
                    _ = await BiometricGate.tryUnlock(reason: "Enable biometric unlock")
                    flow.skipBiometric()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)

            Button("Not now", action: flow.skipBiometric)
                .buttonStyle(.bordered)
        }
    }

    private var doneView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreSuccess)
            Text("You're in.")
        }
    }
}

public struct PINUnlockView: View {
    @State private var pin: String = ""
    @State private var error: String?

    public init() {}

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.lg) {
                Text("Enter PIN").font(.brandHeadlineMedium())
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.brandMono(size: 22))
                    .padding()
                    .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 240)
                if let error {
                    Text(error).foregroundStyle(.bizarreError)
                }
                Button("Unlock") {
                    if PINStore.shared.verify(pin: pin) {
                        // Notify AppState; in the integrated app this flips the phase.
                    } else {
                        error = "Incorrect PIN."
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
            }
            .padding()
        }
    }
}
