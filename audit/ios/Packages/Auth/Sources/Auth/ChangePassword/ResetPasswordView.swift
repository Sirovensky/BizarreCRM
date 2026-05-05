#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §2.8 ResetPasswordViewModel

/// Drives the "complete reset" screen reached from a Universal Link.
@MainActor
@Observable
public final class ResetPasswordViewModel {

    // MARK: - State

    public var newPassword: String = ""
    public var confirmPassword: String = ""
    public var isSubmitting: Bool = false
    public var errorMessage: String? = nil
    public var isSuccess: Bool = false

    // MARK: - Inputs

    /// The token extracted from the Universal Link (one-time use, 15 min TTL).
    private let token: String
    private let api: APIClient

    // MARK: - Init

    public init(token: String, api: APIClient) {
        self.token = token
        self.api = api
    }

    // MARK: - Validation

    public var canSubmit: Bool {
        !newPassword.isEmpty &&
        newPassword == confirmPassword &&
        newPassword.count >= 8 &&
        !isSubmitting
    }

    // MARK: - Submit

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await api.resetPassword(token: token, newPassword: newPassword)
            isSuccess = true
        } catch APITransportError.httpStatus(let code, let msg) {
            switch code {
            case 410:
                errorMessage = "This reset link expired or was already used. Request a new one."
            case 400:
                errorMessage = msg ?? "The new password doesn't meet requirements."
            default:
                errorMessage = msg ?? "Something went wrong. Try again."
            }
        } catch {
            errorMessage = "Couldn't reach the server. Check your connection and try again."
        }
    }
}

// MARK: - §2.8 ResetPasswordView

/// Password-reset completion screen, shown when the user taps the
/// Universal Link `app.bizarrecrm.com/reset-password/:token`.
///
/// - iPhone: full-screen single-column.
/// - iPad: centred glass card (max-width 480 pt).
public struct ResetPasswordView: View {

    @State private var vm: ResetPasswordViewModel
    @FocusState private var focus: Field?

    private let onSuccess: () -> Void

    private enum Field: Hashable {
        case password, confirm
    }

    public init(viewModel: ResetPasswordViewModel, onSuccess: @escaping () -> Void) {
        self._vm = State(wrappedValue: viewModel)
        self.onSuccess = onSuccess
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
        .animation(.smooth(duration: 0.25), value: vm.isSuccess)
        .onChange(of: vm.isSuccess) { _, success in
            if success { onSuccess() }
        }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            ScrollView {
                formContent
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.xxl)
            }
            Spacer()
            ctaSection
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.xl)
        }
    }

    private var iPadLayout: some View {
        ScrollView {
            formContent
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
            // Icon + title
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)

                Text("Set new password")
                    .font(.brandDisplaySmall())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("Choose a strong password — at least 8 characters.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Fields
            BrandSecureField(
                label: "New password",
                text: $vm.newPassword,
                placeholder: "At least 8 characters",
                systemImage: "lock"
            )
            .focused($focus, equals: .password)
            .submitLabel(.next)
            .onSubmit { focus = .confirm }
            .privacySensitive()

            BrandSecureField(
                label: "Confirm password",
                text: $vm.confirmPassword,
                placeholder: "Repeat the password",
                systemImage: "lock.fill"
            )
            .focused($focus, equals: .confirm)
            .submitLabel(.go)
            .onSubmit { Task { await vm.submit() } }
            .privacySensitive()

            // Mismatch hint
            if !vm.confirmPassword.isEmpty && vm.newPassword != vm.confirmPassword {
                Label("Passwords don't match.", systemImage: "exclamationmark.circle.fill")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreError)
                    .accessibilityLabel("Error: passwords don't match.")
            }

            // Error message (expired token, etc.)
            if let err = vm.errorMessage {
                HStack(alignment: .top, spacing: BrandSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.bizarreError)
                        .imageScale(.small)
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreError)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(BrandSpacing.sm)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), tint: Color.bizarreError.opacity(0.10))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - CTA section

    private var ctaSection: some View {
        VStack(spacing: BrandSpacing.md) {
            Button {
                Task { await vm.submit() }
            } label: {
                ZStack {
                    if vm.isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.bizarreOnSurface)
                    } else {
                        Text("Set password")
                            .font(.brandLabelLarge().bold())
                            .foregroundStyle(Color.bizarreOnSurface)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.brandGlassProminent)
            .disabled(!vm.canSubmit)
            .accessibilityLabel(vm.isSubmitting ? "Setting password…" : "Set password")
        }
    }
}

#endif
