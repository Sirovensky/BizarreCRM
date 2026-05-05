#if canImport(SwiftUI)
import SwiftUI

// MARK: - §28.7 `privacySensitive()` on password, PIN, SSN fields
//
// SwiftUI's `.privacySensitive()` modifier hides marked content from
// screenshots taken by the system (e.g. App Switcher / iPad cmd-shift-3
// when redacted-snapshot mode is enabled by SwiftUI's `redactionReasons`)
// and from screen mirroring on supported iOS versions.
//
// We require it on three field classes:
// - **Password** entry / display fields.
// - **PIN** entry / display fields.
// - **SSN / national-ID / tax-ID** display fields (we never collect raw
//   SSNs, but vet/medical tenants display masked tax IDs that must
//   redact under SwiftUI's privacy redaction).
//
// This file centralises the modifier so callers don't have to remember
// which OS guard to apply, and so SwiftLint can flag any
// `SecureField` / PIN field / SSN row that does NOT carry one of these
// helpers.

public extension View {

    /// Marks a password input or password display as privacy-sensitive.
    ///
    /// Apply this on every `SecureField`, on the masked password row in
    /// "show password" reveal flows, and on any "password sent to email"
    /// success/echo screens.
    func passwordPrivate() -> some View {
        modifier(SensitiveFieldPrivacyModifier(category: .password))
    }

    /// Marks a PIN input or PIN display (e.g. shift-handover, manager
    /// override, change-PIN confirm) as privacy-sensitive.
    func pinPrivate() -> some View {
        modifier(SensitiveFieldPrivacyModifier(category: .pin))
    }

    /// Marks an SSN / national-ID / tax-ID display as privacy-sensitive.
    /// We never collect raw SSNs, but masked-tail strings (e.g. "•••-••-1234")
    /// still require redaction under §28.7.
    func ssnPrivate() -> some View {
        modifier(SensitiveFieldPrivacyModifier(category: .ssn))
    }
}

/// Internal modifier — applies SwiftUI's `.privacySensitive()` plus a
/// stable accessibility identifier so UI tests can verify the redaction
/// flag is set without inspecting the private view tree.
struct SensitiveFieldPrivacyModifier: ViewModifier {

    enum Category: String {
        case password
        case pin
        case ssn
    }

    let category: Category

    func body(content: Content) -> some View {
        content
            .privacySensitive(true)
            .accessibilityIdentifier("privacy.sensitive.\(category.rawValue)")
    }
}

#endif
