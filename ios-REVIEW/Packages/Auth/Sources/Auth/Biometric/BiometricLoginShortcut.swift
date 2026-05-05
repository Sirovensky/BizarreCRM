#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - BiometricLoginShortcut view modifier

/// §2 — Pluggable overlay that adds a Face ID / Touch ID quick-login button
/// to any login view.
///
/// **Usage** — attach to whatever host view wraps the credentials panel:
/// ```swift
/// credentialsPanel
///     .biometricLoginShortcut(service: myService, store: myStore) { username, password in
///         // Called when biometric auth succeeds and stored credentials are found.
///         await loginWith(username: username, password: password)
///     }
/// ```
///
/// **Pluggable contract** — this modifier:
/// - Never modifies `LoginFlowView` or any existing Auth file.
/// - Reads the stored username from `LastUsernameStore` and the stored
///   password from `BiometricCredentialStore` after a successful eval.
/// - Delegates the actual network call to the host via `onSuccess`.
/// - Falls through silently on user cancel (no error shown).
/// - Shows an error banner on permission-denied / locked-out states.
///
/// **Liquid Glass chrome** — the biometric button uses `.brandGlass`
/// consistent with other floating CTAs in the app. Both iPhone and iPad
/// display the button identically since it is a small overlay element.
public struct BiometricLoginShortcutModifier: ViewModifier {
    // MARK: - Dependencies
    private let service: BiometricAuthService
    private let usernameStore: LastUsernameStore
    private let credentialStore: BiometricCredentialStore
    private let onSuccess: @Sendable (String, String) async -> Void

    // MARK: - State
    @State private var isAttempting: Bool = false
    @State private var errorMessage: String?
    @State private var availability: BiometricAvailability = .unknown

    // MARK: - Init
    public init(
        service: BiometricAuthService = BiometricAuthService(),
        usernameStore: LastUsernameStore = .shared,
        credentialStore: BiometricCredentialStore = .shared,
        onSuccess: @escaping @Sendable (String, String) async -> Void
    ) {
        self.service = service
        self.usernameStore = usernameStore
        self.credentialStore = credentialStore
        self.onSuccess = onSuccess
    }

    // MARK: - Body
    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if case .available(let kind) = availability, kind != .none {
                    biometricButton(kind: kind)
                        .padding(.bottom, BrandSpacing.lg)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .overlay(alignment: .top) {
                if let msg = errorMessage {
                    errorBanner(message: msg)
                        .padding(.top, BrandSpacing.sm)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(BrandMotion.snappy, value: availability == .unknown)
            .animation(BrandMotion.snappy, value: errorMessage != nil)
            .task {
                availability = service.checkAvailability()
                // Only show the button when there are stored credentials
                // to use; hide it otherwise to avoid a dead-end prompt.
                if case .available = availability {
                    let hasCredentials = await hasStoredCredentials()
                    if !hasCredentials {
                        availability = .unknown
                    }
                }
            }
    }

    // MARK: - Button

    private func biometricButton(kind: BiometricGate.Kind) -> some View {
        Button {
            Task { await attemptBiometricLogin(kind: kind) }
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                if isAttempting {
                    ProgressView()
                        .tint(.bizarreOnSurface)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: kind.sfSymbol)
                        .imageScale(.medium)
                }
                Text("Sign in with \(kind.label)")
                    .font(.brandTitleMedium())
            }
            .foregroundStyle(.bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.base)
            .frame(minHeight: 52)
        }
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16), interactive: true)
        .disabled(isAttempting)
        .accessibilityIdentifier("biometric.loginShortcut")
        .accessibilityLabel("Sign in with \(kind.label)")
    }

    // MARK: - Error banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .imageScale(.small)
            Text(message)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.leading)
            Spacer()
            Button {
                withAnimation(BrandMotion.snappy) { errorMessage = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface1.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("biometric.loginShortcut.error")
    }

    // MARK: - Login flow

    private func attemptBiometricLogin(kind: BiometricGate.Kind) async {
        guard !isAttempting else { return }
        isAttempting = true
        defer { isAttempting = false }
        withAnimation(BrandMotion.snappy) { errorMessage = nil }

        let reason = "Sign in to Bizarre CRM with \(kind.label)"

        do {
            let authenticated = try await service.evaluate(reason: reason)
            guard authenticated else { return }

            let (username, password) = try await loadCredentials()
            await onSuccess(username, password)
        } catch BiometricAuthError.userCancelled {
            // Silent — user deliberately cancelled; fall through to manual login.
            return
        } catch BiometricAuthError.lockedOut {
            withAnimation(BrandMotion.snappy) {
                errorMessage = "Biometrics locked out. Use your PIN to unlock."
            }
        } catch BiometricAuthError.permissionDenied {
            withAnimation(BrandMotion.snappy) {
                errorMessage = "Biometric access denied. Enable it in Settings."
            }
        } catch {
            withAnimation(BrandMotion.snappy) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadCredentials() async throws -> (String, String) {
        guard let u = await usernameStore.lastUsername() else {
            throw BiometricLoginShortcutError.noStoredCredentials
        }
        guard let p = try await credentialStore.loadPassword() else {
            throw BiometricLoginShortcutError.noStoredCredentials
        }
        return (u, p)
    }

    private func hasStoredCredentials() async -> Bool {
        guard let _ = await usernameStore.lastUsername() else { return false }
        guard let _ = try? await credentialStore.loadPassword() else { return false }
        return true
    }
}

// MARK: - Error

public enum BiometricLoginShortcutError: Error, Sendable, LocalizedError {
    case noStoredCredentials

    public var errorDescription: String? {
        "No saved credentials found. Sign in once to enable biometric login."
    }
}

// MARK: - View extension

public extension View {
    /// Adds a Face ID / Touch ID quick-login button overlay. The modifier
    /// hides itself automatically when:
    /// - No biometry hardware is present or enrolled.
    /// - No stored credentials are available.
    ///
    /// - Parameters:
    ///   - service: The `BiometricAuthService` to use. Defaults to a fresh instance.
    ///   - usernameStore: Where the last username lives. Defaults to `.shared`.
    ///   - credentialStore: Where the encrypted password lives. Defaults to `.shared`.
    ///   - onSuccess: Called with `(username, password)` after a successful biometric
    ///     eval + credential retrieval. The host drives the actual network login.
    func biometricLoginShortcut(
        service: BiometricAuthService = BiometricAuthService(),
        usernameStore: LastUsernameStore = .shared,
        credentialStore: BiometricCredentialStore = .shared,
        onSuccess: @escaping @Sendable (String, String) async -> Void
    ) -> some View {
        modifier(BiometricLoginShortcutModifier(
            service: service,
            usernameStore: usernameStore,
            credentialStore: credentialStore,
            onSuccess: onSuccess
        ))
    }
}

#endif
