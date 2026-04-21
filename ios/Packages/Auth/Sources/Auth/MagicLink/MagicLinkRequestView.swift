#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// Token aliases for readability — map onto project palette.
// bizarreOnSurface → primary text; bizarreOnSurfaceMuted → secondary text;
// bizarreOrange → accent; bizarreError → destructive; bizarreSuccess → success.

/// §2 Magic-link login — email request screen + "check your email" confirmation.
///
/// Adapt layout via `Platform.isCompact`:
/// - iPhone: single-column, bottom-anchored CTA.
/// - iPad: centred card, max-width 480 pt.
public struct MagicLinkRequestView: View {

    @State private var vm: MagicLinkViewModel
    @FocusState private var emailFocused: Bool

    public init(viewModel: MagicLinkViewModel) {
        self._vm = State(wrappedValue: viewModel)
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
        .animation(.smooth(duration: 0.28), value: vm.state)
        .accessibilityElement(children: .contain)
    }

    // MARK: - iPhone layout

    @ViewBuilder private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.xxl)
            }
            Spacer()
            ctaSection
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.xl)
        }
    }

    // MARK: - iPad layout

    @ViewBuilder private var iPadLayout: some View {
        ScrollView {
            content
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(.top, BrandSpacing.xxxl)
            ctaSection
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(.bottom, BrandSpacing.xl)
        }
        .padding(.horizontal, BrandSpacing.xl)
    }

    // MARK: - Shared content

    @ViewBuilder private var content: some View {
        switch vm.state {
        case .idle, .sending, .failed:
            requestForm
        case .sent, .verifying, .success:
            sentConfirmation
        }
    }

    // MARK: - Request form

    @ViewBuilder private var requestForm: some View {
        VStack(spacing: BrandSpacing.lg) {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)

                Text("Sign in with Magic Link")
                    .font(.brandTitleLarge())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("Enter your email and we'll send a sign-in link — no password needed.")
                    .font(.brandBodyLarge())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, BrandSpacing.sm)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Email")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)

                TextField("you@example.com", text: $vm.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($emailFocused)
                    .padding(BrandSpacing.base)
                    .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Email address")
                    .submitLabel(.send)
                    .onSubmit { Task { await vm.sendMagicLink() } }
            }

            if let errorMsg = vm.errorMessage {
                Text(errorMsg)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Sent confirmation

    @ViewBuilder private var sentConfirmation: some View {
        VStack(spacing: BrandSpacing.lg) {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.bizarreSuccess)
                    .accessibilityHidden(true)

                Text("Check your email")
                    .font(.brandTitleLarge())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("A sign-in link was sent to **\(vm.email)**. Tap the link in the email to continue.")
                    .font(.brandBodyLarge())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, BrandSpacing.sm)

            if vm.state == .verifying {
                ProgressView()
                    .tint(Color.bizarreOrange)
                    .accessibilityLabel("Verifying sign-in link")
            }
        }
    }

    // MARK: - CTA section

    @ViewBuilder private var ctaSection: some View {
        VStack(spacing: BrandSpacing.md) {
            switch vm.state {
            case .idle, .failed:
                Button {
                    Task { await vm.sendMagicLink() }
                } label: {
                    Group {
                        if vm.state == .sending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Send magic link")
                                .font(.brandBodyMedium().bold())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(BrandSpacing.base)
                }
                .brandGlass(.identity, in: RoundedRectangle(cornerRadius: 14), tint: Color.bizarreOrange, interactive: true)
                .disabled(vm.email.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send magic link")

            case .sending:
                Button { } label: {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(BrandSpacing.base)
                }
                .brandGlass(.identity, in: RoundedRectangle(cornerRadius: 14), tint: Color.bizarreOrange)
                .disabled(true)
                .accessibilityLabel("Sending magic link")

            case .sent, .verifying, .success:
                resendButton
                Button {
                    vm.reset()
                } label: {
                    Text("Use a different email")
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Use a different email address")
            }
        }
    }

    // MARK: - Resend button

    @ViewBuilder private var resendButton: some View {
        Button {
            Task { await vm.sendMagicLink() }
        } label: {
            if vm.resendCooldownRemaining > 0 {
                Text("Resend in \(vm.resendCooldownRemaining)s")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            } else {
                Text("Resend link")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOrange)
            }
        }
        .disabled(vm.resendCooldownRemaining > 0)
        .accessibilityLabel(
            vm.resendCooldownRemaining > 0
            ? "Resend available in \(vm.resendCooldownRemaining) seconds"
            : "Resend magic link"
        )
    }
}
#endif
