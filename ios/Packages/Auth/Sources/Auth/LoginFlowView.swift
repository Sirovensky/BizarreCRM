import SwiftUI
import UIKit
import Core
import DesignSystem
import Networking
import Persistence

public struct LoginFlowView: View {
    @State private var flow: LoginFlow
    @FocusState private var focus: FocusField?
    private let onFinished: (() -> Void)?

    public init(api: APIClient, onFinished: (() -> Void)? = nil) {
        self._flow = State(wrappedValue: LoginFlow(api: api))
        self.onFinished = onFinished
    }

    /// Preview / test convenience — construct a fresh throwaway client.
    public init(onFinished: (() -> Void)? = nil) {
        let client = APIClientImpl(initialBaseURL: ServerURLStore.load())
        self._flow = State(wrappedValue: LoginFlow(api: client))
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            backgroundOrbs
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    header
                    BrandGlassContainer(spacing: 24) {
                        VStack(spacing: BrandSpacing.lg) {
                            StepIndicator(step: flow.step)
                                .padding(.horizontal, BrandSpacing.xl)
                            panel
                                .padding(BrandSpacing.lg)
                                .frame(maxWidth: 480)
                                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 24))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
                                )
                                .padding(.horizontal, BrandSpacing.base)
                                .animation(.smooth(duration: 0.28), value: flow.step)
                        }
                    }
                }
                .padding(.top, BrandSpacing.xl)
                .padding(.bottom, BrandSpacing.xxl)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            if !flow.backupCodes.isEmpty {
                BackupCodesOverlay(codes: flow.backupCodes) {
                    flow.backupCodes = []
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: flow.step) { _, new in
            if case .done = new { onFinished?() }
        }
    }

    // MARK: - Chrome

    private var backgroundOrbs: some View {
        ZStack {
            Circle()
                .fill(.bizarreOrange.opacity(0.25))
                .blur(radius: 140)
                .frame(width: 360, height: 360)
                .offset(x: -160, y: -260)
            Circle()
                .fill(.bizarreMagenta.opacity(0.18))
                .blur(radius: 160)
                .frame(width: 320, height: 320)
                .offset(x: 180, y: 320)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: BrandSpacing.xs) {
            Text("Bizarre CRM")
                .font(.brandDisplayMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(subtitle)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            WaveDivider()
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.top, BrandSpacing.xs)
        }
    }

    private var subtitle: String {
        switch flow.step {
        case .server:           return "Pick your shop."
        case .register:         return "Create a new shop on Bizarre CRM Cloud."
        case .credentials:      return flow.resolvedServerName.map { "Sign in to \($0)." } ?? "Sign in."
        case .setPassword:      return "Set a new password to continue."
        case .twoFactorSetup:   return "Scan the QR with Google Authenticator, 1Password, or Authy."
        case .twoFactorVerify:  return "Enter your 6-digit code."
        case .forgotPassword:   return "We'll email you a reset link."
        case .pinSetup:         return "Create a 4–6 digit PIN for quick unlock."
        case .pinVerify:        return "Enter your PIN."
        case .biometricOffer:   return "Unlock faster next time?"
        case .done:             return "You're in."
        }
    }

    // MARK: - Panel (step switcher)

    @ViewBuilder
    private var panel: some View {
        switch flow.step {
        case .server:          serverPanel
        case .register:        registerPanel
        case .credentials:     credentialsPanel
        case .setPassword:     setPasswordPanel
        case .twoFactorSetup:  twoFactorSetupPanel
        case .twoFactorVerify: twoFactorVerifyPanel
        case .forgotPassword:  forgotPasswordPanel
        case .pinSetup:        pinSetupPanel
        case .pinVerify:       pinVerifyPanel
        case .biometricOffer:  biometricPanel
        case .done:            donePanel
        }
    }

    // MARK: - Step panels

    private var serverPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            if flow.useSelfHosted {
                BrandTextField(
                    label: "Server URL",
                    text: $flow.serverUrlRaw,
                    placeholder: "https://192.168.0.240:443",
                    systemImage: "server.rack",
                    contentType: .URL,
                    keyboard: .URL
                )
                .focused($focus, equals: .serverUrl)
            } else {
                HStack(spacing: 0) {
                    BrandTextField(
                        label: "Shop name",
                        text: $flow.shopSlug,
                        placeholder: "yourshop",
                        systemImage: "storefront",
                        contentType: nil,
                        keyboard: .asciiCapable,
                        autocapitalize: .never,
                        autocorrect: false
                    )
                    .focused($focus, equals: .slug)
                    .onChange(of: flow.shopSlug) { _, new in
                        flow.shopSlug = new.lowercased()
                            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                            .prefix(30)
                            .description
                    }
                    Text(".bizarrecrm.com")
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.leading, BrandSpacing.xs)
                        .padding(.trailing, BrandSpacing.xxs)
                }
            }

            if let name = flow.resolvedServerName {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreSuccess)
                    Text(name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            errorRow

            primaryButton("Continue") { await flow.submitServer() }
                .disabled(flow.useSelfHosted ? flow.serverUrlRaw.isEmpty : flow.shopSlug.count < 3)

            HStack(spacing: BrandSpacing.sm) {
                Button(flow.useSelfHosted ? "Use Bizarre CRM Cloud" : "Self-hosted?") {
                    flow.useSelfHosted.toggle()
                    flow.errorMessage = nil
                }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreTeal)

                Spacer()

                if !flow.useSelfHosted {
                    Button("Create new shop") { flow.beginRegister() }
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreTeal)
                }
            }
        }
    }

    private var registerPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            HStack(spacing: 0) {
                BrandTextField(label: "Shop slug", text: $flow.shopSlug, placeholder: "yourshop",
                               systemImage: "storefront", contentType: nil,
                               keyboard: .asciiCapable, autocapitalize: .never, autocorrect: false)
                Text(".bizarrecrm.com")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.leading, BrandSpacing.xs)
            }
            BrandTextField(label: "Shop name", text: $flow.registerShopName,
                           placeholder: "Main Street Repair",
                           systemImage: "signpost.right")
            BrandTextField(label: "Admin email", text: $flow.registerEmail,
                           placeholder: "owner@example.com",
                           systemImage: "envelope",
                           contentType: .emailAddress, keyboard: .emailAddress,
                           autocapitalize: .never, autocorrect: false)
            BrandSecureField(label: "Password", text: $flow.registerPassword,
                             placeholder: "At least 8 characters",
                             systemImage: "lock")
            errorRow
            primaryButton("Create shop") { await flow.submitRegister() }
            secondaryBackButton
        }
    }

    private var credentialsPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            BrandTextField(label: "Username or email", text: $flow.username,
                           placeholder: "name@example.com",
                           systemImage: "person",
                           contentType: .username, keyboard: .emailAddress,
                           autocapitalize: .never, autocorrect: false)
                .focused($focus, equals: .username)
                .submitLabel(.next)
                .onSubmit { focus = .password }

            BrandSecureField(label: "Password", text: $flow.password,
                             placeholder: "Your password", systemImage: "lock")
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await flow.submitCredentials() } }

            errorRow

            primaryButton("Sign in") { await flow.submitCredentials() }
                .disabled(flow.username.isEmpty || flow.password.isEmpty)

            HStack {
                Button("Forgot password?") { flow.beginForgotPassword() }
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreTeal)
                Spacer()
                Button("Change server") { flow.back() }
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private var setPasswordPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            BrandSecureField(label: "New password", text: $flow.newPassword,
                             placeholder: "At least 8 characters",
                             systemImage: "lock.rotation")
            BrandSecureField(label: "Confirm password", text: $flow.confirmPassword,
                             placeholder: "Type it again",
                             systemImage: "lock.rotation")
            errorRow
            primaryButton("Save and continue") { await flow.submitNewPassword() }
                .disabled(flow.newPassword.count < 8 || flow.newPassword != flow.confirmPassword)
            secondaryBackButton
        }
    }

    private var twoFactorSetupPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            if case let .twoFactorSetup(_, qr) = flow.step, let qr, let image = Self.qrImage(from: qr) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 200, height: 200)
                    .padding(BrandSpacing.md)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            }

            totpField
            errorRow
            primaryButton("Verify code") { await flow.confirmTwoFactorSetup() }
                .disabled(flow.totpCode.filter(\.isNumber).count != 6)
            secondaryBackButton
        }
    }

    private var twoFactorVerifyPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            totpField
            errorRow
            primaryButton("Verify") { await flow.submitTwoFactorVerify() }
                .disabled(flow.totpCode.filter(\.isNumber).count != 6)
            secondaryBackButton
        }
    }

    private var forgotPasswordPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            BrandTextField(label: "Email", text: $flow.forgotEmail,
                           placeholder: "you@example.com",
                           systemImage: "envelope",
                           contentType: .emailAddress, keyboard: .emailAddress,
                           autocapitalize: .never, autocorrect: false)
            if let ok = flow.forgotMessage {
                Text(ok)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreSuccess)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            errorRow
            primaryButton("Send reset link") { await flow.submitForgotPassword() }
                .disabled(!flow.forgotEmail.contains("@"))
            secondaryBackButton
        }
    }

    private var pinSetupPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            BrandSecureField(label: "PIN", text: $flow.pin, placeholder: "4–6 digits",
                             systemImage: "number", keyboard: .numberPad)
            BrandSecureField(label: "Confirm PIN", text: $flow.confirmPin, placeholder: "Type it again",
                             systemImage: "number", keyboard: .numberPad)
            errorRow
            primaryButton("Save PIN") { flow.enrollPIN() }
                .disabled(flow.pin.count < 4 || flow.pin.count > 6)
        }
    }

    private var pinVerifyPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            BrandSecureField(label: "PIN", text: $flow.pin, placeholder: "Enter PIN",
                             systemImage: "number", keyboard: .numberPad)
            errorRow
        }
    }

    private var biometricPanel: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreOrange)
            Text("Unlock quickly with Face ID or Touch ID.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
            primaryButton("Enable") {
                _ = await BiometricGate.tryUnlock(reason: "Enable biometric unlock")
                flow.skipBiometric()
            }
            Button("Not now", action: flow.skipBiometric)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.top, BrandSpacing.xs)
        }
    }

    private var donePanel: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreSuccess)
            Text("Signed in.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
        }
    }

    // MARK: - Shared pieces

    private var totpField: some View {
        HStack {
            Image(systemName: "number.circle")
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("000 000", text: $flow.totpCode)
                .font(.brandMono(size: 22))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode)
                .kerning(6)
                .onChange(of: flow.totpCode) { _, new in
                    flow.totpCode = String(new.filter(\.isNumber).prefix(6))
                }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5))
    }

    @ViewBuilder
    private var errorRow: some View {
        if let err = flow.errorMessage {
            HStack(alignment: .top, spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreError)
                Text(err)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreError)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if flow.isSubmitting { ProgressView().tint(.bizarreOnOrange) }
                Text(title).font(.brandTitleMedium()).bold()
            }
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .foregroundStyle(.bizarreOnOrange)
        .disabled(flow.isSubmitting)
    }

    private var secondaryBackButton: some View {
        Button("Back", action: flow.back)
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOnSurfaceMuted)
    }

    // MARK: - Helpers

    private enum FocusField: Hashable {
        case slug, serverUrl, username, password
    }

    private static func qrImage(from base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Step indicator

private struct StepIndicator: View {
    let step: LoginFlow.Step

    var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            bar(filled: filled(0))
            bar(filled: filled(1))
            bar(filled: filled(2))
            bar(filled: filled(3))
        }
        .frame(height: 4)
    }

    private func bar(filled: Bool) -> some View {
        Capsule()
            .fill(filled ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: 4)
    }

    private func filled(_ index: Int) -> Bool {
        switch step {
        case .server, .register:      return index == 0
        case .credentials,
             .forgotPassword:         return index <= 1
        case .setPassword,
             .twoFactorSetup,
             .twoFactorVerify:        return index <= 2
        case .pinSetup,
             .pinVerify,
             .biometricOffer,
             .done:                   return true
        }
    }
}

// MARK: - Form field helpers

private struct BrandTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let systemImage: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var autocapitalize: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            HStack {
                Image(systemName: systemImage).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField(placeholder, text: $text)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(autocapitalize)
                    .autocorrectionDisabled(!autocorrect)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5))
        }
    }
}

private struct BrandSecureField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let systemImage: String
    var keyboard: UIKeyboardType = .default
    @State private var reveal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            HStack {
                Image(systemName: systemImage).foregroundStyle(.bizarreOnSurfaceMuted)
                if reveal {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: $text)
                        .keyboardType(keyboard)
                }
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5))
        }
    }
}

// MARK: - Backup codes overlay

private struct BackupCodesOverlay: View {
    let codes: [String]
    let onDismiss: () -> Void
    @State private var acknowledged: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreOrange)
                Text("Save your backup codes")
                    .font(.brandHeadlineMedium())
                Text("If you lose access to your authenticator, each of these one-time codes will let you sign in.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    ForEach(Array(codes.enumerated()), id: \.offset) { idx, code in
                        HStack {
                            Text("\(idx + 1).").foregroundStyle(.bizarreOnSurfaceMuted)
                            Text(code).font(.brandMono(size: 16))
                            Spacer()
                        }
                    }
                }
                .padding(BrandSpacing.md)
                .frame(maxWidth: .infinity)
                .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12))

                Toggle("I've saved these somewhere safe", isOn: $acknowledged)
                    .font(.brandBodyMedium())
                    .tint(.bizarreOrange)

                Button("Continue") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .frame(maxWidth: .infinity)
                    .disabled(!acknowledged)
            }
            .padding(BrandSpacing.lg)
            .frame(maxWidth: 420)
            .background(Color.bizarreSurface1.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
            .padding(BrandSpacing.lg)
        }
    }
}

// MARK: - PIN unlock (cold start)

public struct PINUnlockView: View {
    @State private var pin: String = ""
    @State private var error: String?
    public var onUnlock: (() -> Void)? = nil

    public init(onUnlock: (() -> Void)? = nil) {
        self.onUnlock = onUnlock
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreOrange)
                Text("Enter PIN").font(.brandHeadlineMedium())
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.brandMono(size: 22))
                    .padding()
                    .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 240)
                if let error {
                    Text(error).foregroundStyle(.bizarreError)
                }
                Button("Unlock") {
                    if PINStore.shared.verify(pin: pin) {
                        onUnlock?()
                    } else {
                        error = "Incorrect PIN."
                        pin = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
            }
            .padding()
        }
    }
}
