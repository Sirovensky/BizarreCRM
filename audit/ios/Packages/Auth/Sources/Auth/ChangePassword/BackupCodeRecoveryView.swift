#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §2.8 BackupCodeRecoveryViewModel

/// Drives the backup-code recovery screen.
///
/// Flow: User enters username + password + one backup code
/// → `POST /auth/recover-with-backup-code`
/// → on success, the `recoveryToken` is used as the challengeToken
///   for the SetPassword step (so the user picks a new password and
///   also re-enrolls 2FA).
///
/// This is reached from the "Forgot password" screen when the user
/// chooses "Use a backup code instead".
@MainActor
@Observable
public final class BackupCodeRecoveryViewModel {

    // MARK: - State

    public var username: String = ""
    public var password: String = ""
    public var backupCode: String = ""

    public var isSubmitting: Bool = false
    public var errorMessage: String? = nil

    /// Set on success; caller observes and pushes SetPassword.
    public var recoveryToken: String? = nil

    // MARK: - Dependencies

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient, usernameHint: String = "") {
        self.api = api
        self.username = usernameHint
    }

    // MARK: - Validation

    public var canSubmit: Bool {
        !username.isEmpty &&
        !password.isEmpty &&
        backupCode.count >= 8 &&
        !isSubmitting
    }

    // MARK: - Submit

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let normalised = backupCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .uppercased()

        do {
            let response = try await api.recoverWithBackupCode(
                username: username,
                password: password,
                backupCode: normalised
            )
            recoveryToken = response.recoveryToken
        } catch APITransportError.httpStatus(let code, let msg) {
            switch code {
            case 400:
                errorMessage = "Invalid backup code. Check it and try again."
            case 401:
                errorMessage = "Username or password is incorrect."
            case 404:
                errorMessage = "No account found with that username."
            case 410:
                errorMessage = "This backup code has already been used. Try another."
            case 429:
                errorMessage = "Too many attempts. Wait a moment and try again."
            default:
                errorMessage = msg ?? "Something went wrong. Try again."
            }
        } catch {
            errorMessage = "Couldn't reach the server. Check your connection and try again."
        }
    }
}

// MARK: - §2.8 BackupCodeRecoveryView

/// Backup-code recovery screen reached from "Forgot password".
///
/// - iPhone: full-screen single-column with sticky CTA.
/// - iPad: centred glass card (max-width 480 pt).
public struct BackupCodeRecoveryView: View {

    @State private var vm: BackupCodeRecoveryViewModel
    @FocusState private var focus: Field?

    /// Called with the `recoveryToken` on success. Caller pushes SetPassword.
    private let onSuccess: (String) -> Void
    private let onCancel: () -> Void

    private enum Field: Hashable {
        case username, password, backupCode
    }

    public init(
        viewModel: BackupCodeRecoveryViewModel,
        onSuccess: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._vm = State(wrappedValue: viewModel)
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            Group {
                if Platform.isCompact {
                    iPhoneLayout
                } else {
                    iPadLayout
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.25), value: vm.recoveryToken != nil)
        .onChange(of: vm.recoveryToken) { _, token in
            if let token { onSuccess(token) }
        }
        .navigationTitle("Recover access")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Cancel recovery")
            }
        }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            ScrollView {
                formContent
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.xxl)
                    .padding(.bottom, BrandSpacing.lg)
            }
            ctaSection
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.xl)
        }
    }

    private var iPadLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xxl) {
                formContent
                ctaSection
            }
            .frame(maxWidth: 480)
            .padding(BrandSpacing.xxxl)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
            .padding(.horizontal, BrandSpacing.xxl)
            .padding(.top, BrandSpacing.xl)
        }
    }

    // MARK: - Form content

    private var formContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Image(systemName: "key.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)

                Text("Use a backup code")
                    .font(.brandDisplaySmall())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("Enter your credentials and one of the backup codes you saved when you set up 2FA. Each code can only be used once.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Fields
            BrandTextField(
                "Username",
                text: $vm.username,
                hint: "your_username"
            )
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($focus, equals: .username)
            .submitLabel(.next)
            .onSubmit { focus = .password }

            BrandSecureField(
                label: "Password",
                text: $vm.password,
                placeholder: "Your password",
                systemImage: "lock"
            )
            .focused($focus, equals: .password)
            .submitLabel(.next)
            .onSubmit { focus = .backupCode }
            .privacySensitive()

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                BrandTextField(
                    "Backup code",
                    text: $vm.backupCode,
                    hint: "XXXX-XXXXXXXX"
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .focused($focus, equals: .backupCode)
                .submitLabel(.go)
                .onSubmit { Task { await vm.submit() } }
                .font(.system(.body, design: .monospaced))

                Text("From the list you saved during 2FA setup.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }

            // Error
            if let err = vm.errorMessage {
                errorCard(err)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.bizarreError)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.sm)
        .brandGlass(.regular,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                    tint: Color.bizarreError.opacity(0.10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - CTA section

    private var ctaSection: some View {
        Button {
            Task { await vm.submit() }
        } label: {
            ZStack {
                if vm.isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.bizarreOnSurface)
                } else {
                    Text("Recover access")
                        .font(.brandLabelLarge().bold())
                        .foregroundStyle(Color.bizarreOnSurface)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.brandGlassProminent)
        .disabled(!vm.canSubmit)
        .accessibilityLabel(vm.isSubmitting ? "Recovering…" : "Recover access")
    }
}

#endif
