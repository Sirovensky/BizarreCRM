#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - §2.13 Screenshot / screen-recording blur for sensitive auth screens

/// A view modifier that applies a blur overlay whenever iOS detects that the
/// screen is being captured (mirrored, recorded, or screenshot captured via
/// `UIScreen.isCaptured` / `UIScreen.capturedDidChangeNotification`).
///
/// Apply to any view that shows passwords, 2FA codes, or backup codes:
/// ```swift
/// TwoFactorSetupPanel()
///     .sensitiveScreenBlur()
/// ```
public struct SensitiveScreenBlurModifier: ViewModifier {

    @State private var isCaptured: Bool = UIScreen.main.isCaptured

    public func body(content: Content) -> some View {
        content
            .blur(radius: isCaptured ? 20 : 0)
            .overlay {
                if isCaptured {
                    ZStack {
                        Color.bizarreSurfaceBase.opacity(0.7).ignoresSafeArea()
                        VStack(spacing: 12) {
                            Image(systemName: "eye.slash.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Text("Screen hidden while recording")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIScreen.capturedDidChangeNotification
                )
            ) { _ in
                isCaptured = UIScreen.main.isCaptured
            }
            .animation(.easeInOut(duration: 0.2), value: isCaptured)
    }
}

public extension View {
    /// Blur and overlay this view whenever the screen is being captured.
    /// Apply to password, 2FA, and backup-code screens.
    func sensitiveScreenBlur() -> some View {
        modifier(SensitiveScreenBlurModifier())
    }
}

#endif
