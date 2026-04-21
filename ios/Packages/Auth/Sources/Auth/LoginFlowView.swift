#if canImport(UIKit)
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
        case .setPassword:      return "Your admin requested a reset. Choose a new password to continue."
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
        // Evaluate once per render. The evaluator is pure so this is cheap
        // and re-runs automatically when `flow.newPassword` mutates.
        let evaluation = PasswordStrengthEvaluator.evaluate(flow.newPassword)
        let mismatch = !flow.confirmPassword.isEmpty && flow.newPassword != flow.confirmPassword

        return VStack(alignment: .leading, spacing: BrandSpacing.md) {
            BrandSecureField(label: "New password", text: $flow.newPassword,
                             placeholder: "At least 8 characters",
                             systemImage: "lock.rotation")
                .accessibilityIdentifier("setPassword.new")

            if !flow.newPassword.isEmpty {
                PasswordStrengthMeter(evaluation: evaluation)
                    .padding(.horizontal, BrandSpacing.xxs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            BrandSecureField(label: "Confirm password", text: $flow.confirmPassword,
                             placeholder: "Type it again",
                             systemImage: "lock.rotation")
                .accessibilityIdentifier("setPassword.confirm")

            if mismatch {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.bizarreWarning)
                        .imageScale(.small)
                    Text("Passwords don't match yet.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreWarning)
                }
                .accessibilityElement(children: .combine)
            }

            errorRow

            primaryButton("Save and continue") { await flow.submitNewPassword() }
                .disabled(!evaluation.rules.allPassed || flow.newPassword != flow.confirmPassword)
                .accessibilityIdentifier("setPassword.submit")

            secondaryBackButton
        }
        .animation(BrandMotion.snappy, value: flow.newPassword.isEmpty)
        .animation(BrandMotion.snappy, value: mismatch)
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
            if flow.useBackupCode {
                backupCodeField
            } else {
                totpField
            }

            errorRow

            primaryButton("Verify") { await flow.submitTwoFactorVerify() }
                .disabled(verifyDisabled)
                .accessibilityIdentifier(flow.useBackupCode ? "twoFactor.verifyBackup" : "twoFactor.verify")

            Button {
                withAnimation(BrandMotion.snappy) { flow.toggleBackupCode() }
            } label: {
                Text(flow.useBackupCode ? "Use authenticator code instead" : "Use a backup code instead")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreTeal)
            }
            .accessibilityIdentifier("twoFactor.toggleBackup")

            secondaryBackButton
        }
    }

    /// Disable the CTA until the input is the right shape for the chosen path.
    private var verifyDisabled: Bool {
        if flow.useBackupCode {
            return flow.backupCodeInput.filter { $0.isLetter || $0.isNumber }.count < 8
        }
        return flow.totpCode.filter(\.isNumber).count != 6
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
        let kind = BiometricGate.kind
        let kindLabel = kind == .none ? "biometrics" : kind.label
        return VStack(spacing: BrandSpacing.md) {
            Image(systemName: kind == .none ? "lock.fill" : kind.sfSymbol)
                .font(.system(size: 64))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Unlock quickly with \(kindLabel).")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            primaryButton("Enable") {
                let ok = await BiometricGate.tryUnlock(
                    reason: "Enable \(kindLabel) for Bizarre CRM"
                )
                if ok {
                    flow.acceptBiometric()
                } else {
                    // User cancelled or eval failed — keep biometric off.
                    // They can still enable later in Settings.
                    flow.skipBiometric()
                }
            }
            .accessibilityIdentifier("biometric.enable")
            Button("Not now", action: flow.skipBiometric)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.top, BrandSpacing.xs)
                .accessibilityIdentifier("biometric.skip")
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
                .accessibilityHidden(true)
            TextField("000 000", text: $flow.totpCode)
                .font(.brandMono(size: 22))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode)
                .kerning(6)
                .accessibilityLabel("Six-digit authenticator code")
                .accessibilityIdentifier("twoFactor.totpField")
                .onChange(of: flow.totpCode) { _, new in
                    flow.totpCode = String(new.filter(\.isNumber).prefix(6))
                }
        }
        .padding(BrandSpacing.md)
        .frame(minHeight: 52)
        .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5))
    }

    private var backupCodeField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text("Backup code").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "key")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("XXXX-XXXX", text: $flow.backupCodeInput)
                    .font(.brandMono(size: 18))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .kerning(4)
                    .accessibilityLabel("Backup code")
                    .accessibilityHint("Enter one of the backup codes you saved during setup")
                    .accessibilityIdentifier("twoFactor.backupField")
                    .onChange(of: flow.backupCodeInput) { _, new in
                        // Accept Crockford base32 only (letters + digits).
                        // Upper-case live so the user can see what will be sent.
                        flow.backupCodeInput = new
                            .uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                            .prefix(24)
                            .description
                    }
            }
            .padding(BrandSpacing.md)
            .frame(minHeight: 52)
            .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5))

            Text("Each code works once. Contact your admin if you've used them all.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
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

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: systemImage).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField(placeholder, text: $text)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(autocapitalize)
                    .autocorrectionDisabled(!autocorrect)
                    .focused($focused)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.base)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
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
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: systemImage).foregroundStyle(.bizarreOnSurfaceMuted)
                Group {
                    if reveal {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboard)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(placeholder, text: $text)
                            .keyboardType(keyboard)
                    }
                }
                .focused($focused)
                .frame(maxWidth: .infinity, minHeight: 28)

                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.base)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
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
//
// §2.5 — Custom keypad over a SecureField. Reasons to roll our own:
//
// - The system number-pad hides the tap targets behind IME which breaks
//   Dynamic Type (VoiceOver users get an unlabelled text field).
// - We want explicit hit targets with 44pt minimums and haptic feedback
//   per entered digit.
// - Lockout UX (live countdown + revoked→re-auth handoff) has no clean
//   place to sit on the system keyboard.

public struct PINUnlockView: View {
    @State private var pin: String = ""
    @State private var error: String?
    @State private var lockoutEndsAt: Date?
    @State private var tick: Date = Date()
    @State private var hideTimer: Task<Void, Never>?
    @State private var didAttemptBiometric: Bool = false
    public var onUnlock: (() -> Void)?
    public var onRevoked: (() -> Void)?

    /// Hard max — matches the enrolment `4 ≤ pin ≤ 6`.
    private let pinHardMax = 6

    /// Actual enrolled PIN length (persisted during `enrol`). Falls back
    /// to `pinHardMax` when nothing is enrolled — the view should never
    /// render in that state, but we degrade to a 6-dot layout rather
    /// than crash.
    private var pinExpectedLength: Int {
        PINStore.shared.enrolledLength ?? pinHardMax
    }

    public init(onUnlock: (() -> Void)? = nil, onRevoked: (() -> Void)? = nil) {
        self.onUnlock = onUnlock
        self.onRevoked = onRevoked
    }

    private var biometricEnabledAndAvailable: Bool {
        BiometricPreference.shared.isEnabled && BiometricGate.isAvailable
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: BrandSpacing.xl)

                        VStack(spacing: BrandSpacing.md) {
                            VStack(spacing: BrandSpacing.xs) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.bizarreOrange)
                                    .accessibilityHidden(true)
                                Text("Enter your PIN")
                                    .font(.brandHeadlineMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                    .accessibilityAddTraits(.isHeader)
                                Text("You signed in on this device earlier.")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                    .multilineTextAlignment(.center)
                            }

                            dotRow
                                .padding(.top, BrandSpacing.xs)
                                .accessibilityLabel("Entered digits")
                                .accessibilityValue("\(pin.count) of \(pinExpectedLength)")

                            // Reserved status row — error / lockout never
                            // pushes the keypad down.
                            Group {
                                if let error {
                                    Text(error)
                                        .font(.brandLabelLarge())
                                        .foregroundStyle(.bizarreError)
                                        .accessibilityIdentifier("pin.error")
                                } else if let until = lockoutEndsAt, until > tick {
                                    let remaining = Int(until.timeIntervalSince(tick).rounded(.up))
                                    Text("Too many wrong tries. Try again in \(remaining)s.")
                                        .font(.brandLabelLarge())
                                        .foregroundStyle(.bizarreWarning)
                                        .multilineTextAlignment(.center)
                                        .accessibilityIdentifier("pin.lockoutCountdown")
                                } else {
                                    Text(" ")
                                        .font(.brandLabelLarge())
                                        .foregroundStyle(.clear)
                                }
                            }
                            .frame(minHeight: 22)

                            PINKeypad(
                                onDigit: { append($0) },
                                onBackspace: { backspace() },
                                isLocked: isLocked
                            )
                            .padding(.top, BrandSpacing.xs)

                            if biometricEnabledAndAvailable {
                                Button {
                                    Task { await attemptBiometric(triggeredByUser: true) }
                                } label: {
                                    Label("Use \(BiometricGate.kind.label)",
                                          systemImage: BiometricGate.kind.sfSymbol)
                                        .font(.brandLabelLarge())
                                        .foregroundStyle(.bizarreTeal)
                                }
                                .accessibilityIdentifier("pin.biometric")
                                .padding(.top, BrandSpacing.sm)
                            }
                        }
                        .padding(.horizontal, BrandSpacing.base)
                        .frame(maxWidth: 420)

                        Spacer(minLength: BrandSpacing.md)

                        // Secondary-tier escape hatch sits at the bottom,
                        // small + muted, so thumbs don't hit it while
                        // typing digits. 44pt tap area preserved.
                        Button {
                            onRevoked?()
                        } label: {
                            Text("Forgot your PIN?  ·  Sign in again")
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .padding(.vertical, BrandSpacing.sm)
                                .frame(minHeight: 44)
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("pin.reauth")
                        .padding(.bottom, BrandSpacing.lg)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            lockoutEndsAt = PINStore.shared.lockoutEndsAt
            startTicking()
            // Auto-prompt biometric on first appearance if the user
            // opted in and the device is capable. If they cancel, they
            // fall through to the PIN keypad — no re-prompt.
            if !didAttemptBiometric, biometricEnabledAndAvailable, !isLocked {
                didAttemptBiometric = true
                Task { await attemptBiometric(triggeredByUser: false) }
            }
        }
        .onDisappear { hideTimer?.cancel() }
    }

    /// Run a biometric evaluation. Success unlocks + resets the PIN
    /// failure counter so a legit user doesn't carry old failed tries.
    /// Failure / cancel is silent — user can still try the keypad or
    /// the manual biometric button.
    private func attemptBiometric(triggeredByUser: Bool) async {
        let ok = await BiometricGate.tryUnlock(reason: "Unlock Bizarre CRM")
        guard ok else { return }
        // Successful bio evidence of owner — clear any accumulated PIN
        // failure counter but KEEP the enrolled hash so PIN still works.
        PINStore.shared.clearFailures()
        onUnlock?()
    }

    private var isLocked: Bool {
        if let until = lockoutEndsAt, until > tick { return true }
        return false
    }

    /// N dots matching the enrolled PIN length so users don't think they
    /// need to type a longer PIN than they actually set up. Filled dots
    /// track current entry length; unfilled slots render at lower opacity.
    private var dotRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            ForEach(0..<pinExpectedLength, id: \.self) { idx in
                Circle()
                    .fill(idx < pin.count ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.4))
                    .frame(width: 14, height: 14)
                    .animation(BrandMotion.snappy, value: pin.count)
            }
        }
    }

    private func append(_ digit: String) {
        guard !isLocked, pin.count < pinHardMax else { return }
        error = nil
        pin.append(digit)
        BrandHaptics.tap()
        // Auto-submit strategy agnostic to stored PIN length so legacy
        // installs without `pin_length` still unlock:
        //   • at max (6) → fire immediately (no more digits possible).
        //   • at >= 4  → fire after 500ms debounce (cancelled by the
        //     next keystroke). Covers 4- and 5-digit PINs without
        //     blocking 6-digit users behind a never-reached match.
        if pin.count >= pinHardMax {
            hideTimer?.cancel()
            submit()
        } else if pin.count >= 4 {
            autoSubmit(after: 0.5)
        }
    }

    private func backspace() {
        guard !isLocked, !pin.isEmpty else { return }
        error = nil
        pin.removeLast()
        BrandHaptics.tap()
        hideTimer?.cancel()
    }

    private func autoSubmit(after delay: TimeInterval) {
        hideTimer?.cancel()
        hideTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            submit()
        }
    }

    private func submit() {
        guard pin.count >= 4, pin.count <= pinHardMax else { return }
        switch PINStore.shared.verify(pin: pin) {
        case .ok:
            pin = ""
            onUnlock?()
        case .wrong(let remaining):
            error = remaining > 0 ? "Incorrect PIN. \(remaining) \(remaining == 1 ? "try" : "tries") left." : "Incorrect PIN."
            pin = ""
        case .lockedOut(let until):
            lockoutEndsAt = until
            pin = ""
        case .revoked:
            pin = ""
            onRevoked?()
        }
    }

    /// Live ticker for the lockout countdown. Runs only while the view is
    /// visible so battery / background work is zero when signed in.
    private func startTicking() {
        Task { @MainActor in
            while !Task.isCancelled {
                tick = Date()
                if let until = lockoutEndsAt, until <= tick {
                    lockoutEndsAt = nil
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

/// 3-column numeric keypad with square circular keys. Each cell is
/// clamped to a 1:1 aspect ratio so `Circle()` never stretches into an
/// ellipse when the container is wider than tall. Disabled when `isLocked`.
private struct PINKeypad: View {
    let onDigit: (String) -> Void
    let onBackspace: () -> Void
    let isLocked: Bool

    /// Max diameter — keeps keys pleasant on iPhone 12 through iPhone 17
    /// Pro Max + iPad (where the `.frame(maxWidth: 320)` on the grid
    /// container keeps the whole pad from stretching edge-to-edge).
    private let maxKeyDiameter: CGFloat = 76

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(1...3, id: \.self) { col in
                        let digit = row * 3 + col
                        keyButton(label: "\(digit)") { onDigit("\(digit)") }
                    }
                }
            }
            HStack(spacing: BrandSpacing.sm) {
                // Empty placeholder preserves 3-column symmetry so 0 sits
                // center-bottom, matching iOS system keypads.
                Color.clear.aspectRatio(1, contentMode: .fit)
                keyButton(label: "0") { onDigit("0") }
                backspaceButton
            }
        }
        .frame(maxWidth: 320)
        .disabled(isLocked)
        .opacity(isLocked ? 0.5 : 1.0)
    }

    private func keyButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(Color.bizarreSurface2.opacity(0.7), in: Circle())
                .overlay(Circle().strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                .frame(maxWidth: maxKeyDiameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Digit \(label)")
    }

    private var backspaceButton: some View {
        Button(action: onBackspace) {
            Image(systemName: "delete.left")
                .font(.title2)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(minWidth: 64, minHeight: 64)
                .frame(maxWidth: .infinity)
                .background(Color.bizarreSurface2.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete last digit")
    }
}

#endif

