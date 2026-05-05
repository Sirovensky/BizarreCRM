#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - SessionRevokedBanner
//
// §2.11 — Glass banner shown when the server posts a session-revoke event:
// "Signed out — session was revoked on another device." with reason from
// `message`. Dismisses automatically after 6s or on explicit tap.
//
// Usage — attach to the root view or login screen:
//   .sessionRevokedBanner(message: $revokeMessage)
// where `revokeMessage` is set by the SessionEvents listener.

public struct SessionRevokedBanner: View {
    let message: String
    let onDismiss: () -> Void

    @State private var autoTimer: Task<Void, Never>? = nil

    public init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.bizarreError)
                .imageScale(.medium)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Signed out")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(message.isEmpty ? "Your session was revoked on another device." : message)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            Button {
                withAnimation(BrandMotion.snappy) { onDismiss() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreError.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signed out. \(message.isEmpty ? "Your session was revoked on another device." : message)")
        .onAppear {
            autoTimer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(BrandMotion.snappy) { onDismiss() }
            }
        }
        .onDisappear { autoTimer?.cancel() }
    }
}

// MARK: - View modifier

private struct SessionRevokedBannerModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let msg = message {
                SessionRevokedBanner(message: msg) {
                    message = nil
                }
                .padding(.top, BrandSpacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(BrandMotion.snappy, value: message != nil)
                .zIndex(999)
            }
        }
    }
}

public extension View {
    /// Overlays a session-revoked glass banner when `message` is non-nil.
    /// Set `message` from a `SessionEvents` subscriber.
    func sessionRevokedBanner(message: Binding<String?>) -> some View {
        modifier(SessionRevokedBannerModifier(message: message))
    }
}

#endif
