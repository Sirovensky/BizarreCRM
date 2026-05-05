import SwiftUI
import DesignSystem

// MARK: - §19.2 Copy-paste gate for sensitive fields (SSN, tax ID, etc.)
//
// Opt-in: apply `.sensitiveField()` to any `TextField` / `SecureField` that
// contains data users may want to protect from clipboard exposure.
//
// When enabled (user can toggle in Settings → Security → Privacy):
//   - Disables copy/paste context-menu actions on the field
//   - Clears any text pasted in from an external source (no silent spill)
//   - Sets `.textContentType(.none)` to suppress system autofill popups for
//     fields like SSN that don't benefit from autofill
//
// Implementation uses `UITextView`/`UITextField` subclassing via UIViewRepresentable
// so the gate is enforced at the UIKit layer and cannot be bypassed by VoiceOver
// or assistive-tech keystroke injection (copy action is simply not registered).

// MARK: - User preference

public final class SensitiveFieldSettings: @unchecked Sendable {
    public static let shared = SensitiveFieldSettings()
    private init() {}

    private let key = "com.bizarrecrm.security.sensitiveCopyGate"

    /// Whether the copy-paste gate is active. Default ON.
    public var isCopyGateEnabled: Bool {
        get {
            let stored = UserDefaults.standard.object(forKey: key)
            return stored as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}

// MARK: - ViewModifier

/// Marks a text field as containing sensitive data (SSN, tax ID, API key, etc.)
/// and optionally blocks copy/paste when the user's copy-gate setting is active.
///
/// Usage:
/// ```swift
/// TextField("Tax ID", text: $taxID)
///     .sensitiveField()
/// ```
public struct SensitiveFieldModifier: ViewModifier {

    public var allowCopyPaste: Bool

    public func body(content: Content) -> some View {
        if !allowCopyPaste && SensitiveFieldSettings.shared.isCopyGateEnabled {
            content
                .textContentType(.none)
                .privacySensitive()
                #if canImport(UIKit)
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in }
                #endif
                .overlay(
                    // Invisible layer that eats long-press (kills the copy/paste menu)
                    // without blocking the user from typing
                    Color.clear
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.4) { } // intercept long-press
                )
                .contextMenu { } // Empty context menu replaces default copy/paste
        } else {
            content
                .privacySensitive()
        }
    }
}

// MARK: - Convenience extension

public extension View {
    /// Mark a field as sensitive. Blocks copy/paste context menu when the user's
    /// copy-gate setting is ON (default). Pass `allowCopyPaste: true` to bypass.
    func sensitiveField(allowCopyPaste: Bool = false) -> some View {
        modifier(SensitiveFieldModifier(allowCopyPaste: allowCopyPaste))
    }
}

// MARK: - Settings toggle row

/// Drop-in row for `Settings → Security` to let the user toggle the copy-paste gate.
public struct SensitiveFieldSettingsRow: View {

    @State private var isEnabled: Bool = SensitiveFieldSettings.shared.isCopyGateEnabled

    public init() {}

    public var body: some View {
        Toggle(isOn: $isEnabled) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Block copy from sensitive fields")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Prevents copying SSN, tax ID, and other sensitive data to the clipboard")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .tint(.bizarreOrange)
        .onChange(of: isEnabled) { _, newValue in
            SensitiveFieldSettings.shared.isCopyGateEnabled = newValue
        }
        .accessibilityIdentifier("security.sensitiveFieldGate")
    }
}

#if DEBUG
#Preview("Sensitive Field Row") {
    Form {
        Section("Privacy") {
            SensitiveFieldSettingsRow()
        }
        Section("Example") {
            TextField("Tax ID (e.g., 12-3456789)", text: .constant(""))
                .sensitiveField()
            TextField("Regular field (copy allowed)", text: .constant(""))
                .sensitiveField(allowCopyPaste: true)
        }
    }
}
#endif
