import Foundation
import SwiftUI

// MARK: - §2.13 Shared-device mode hides biometric

/// When shared-device mode is active, biometric unlock is hidden to avoid
/// confusion (multiple staff on one device would cross-auth each other's
/// biometric data — a security risk and a UX footgun).
///
/// Use this modifier on any view that conditionally shows a "Use Face ID"
/// or "Use Touch ID" button:
///
/// ```swift
/// if canShowBiometric {
///     BiometricLoginButton(...)
/// }
/// ```
///
/// becomes:
///
/// ```swift
/// if canShowBiometric {
///     BiometricLoginButton(...)
///         .hiddenInSharedDeviceMode()
/// }
/// ```
///
/// The modifier is a no-op when shared-device mode is inactive.
public struct HiddenInSharedDeviceModeModifier: ViewModifier {
    @State private var isSharedDevice: Bool = false

    public func body(content: Content) -> some View {
        content
            .opacity(isSharedDevice ? 0 : 1)
            .allowsHitTesting(!isSharedDevice)
            .accessibilityHidden(isSharedDevice)
            .task {
                isSharedDevice = await SharedDeviceManager.shared.isSharedDevice
            }
    }
}

public extension View {
    /// Hides (opacity 0, no interaction) this view when shared-device mode is active.
    func hiddenInSharedDeviceMode() -> some View {
        modifier(HiddenInSharedDeviceModeModifier())
    }
}

// MARK: - SharedDeviceBiometricAvailability

/// Combines `BiometricGate.isAvailable` with shared-device suppression.
///
/// Use in view models or views to decide whether to offer biometric:
/// ```swift
/// let canUseBiometric = await SharedDeviceBiometricAvailability.isAvailable
/// ```
public enum SharedDeviceBiometricAvailability {
    /// `true` only when biometrics are enrolled AND shared-device mode is OFF.
    public static var isAvailable: Bool {
        get async {
            let sharedDevice = await SharedDeviceManager.shared.isSharedDevice
            guard !sharedDevice else { return false }
            return BiometricGate.isAvailable
        }
    }
}
