import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// §22.7 — Field validation keys: IMEI/phone `.numberPad`; email
// `.emailAddress`; URL `.URL`; search `.webSearch`.
//
// Centralises the mapping between a field's *semantic* role and the
// `UIKeyboardType` / `UITextContentType` / autocorrect / autocap settings
// it should adopt.  Call sites declare intent rather than hand-tuning
// six modifiers per field.
//
// Usage:
//   TextField("Phone", text: $phone).brandFieldKeyboard(.phone)
//   TextField("Email", text: $email).brandFieldKeyboard(.email)
//   TextField("URL",   text: $url  ).brandFieldKeyboard(.url)
//   TextField("Search", text: $q   ).brandFieldKeyboard(.search)
//   TextField("IMEI",  text: $imei ).brandFieldKeyboard(.imei)
//   TextField("ID",    text: $id   ).brandFieldKeyboard(.identifier)

// MARK: - Semantic role

/// Semantic input role used by `.brandFieldKeyboard(_:)` (§22.7).
public enum FieldKeyboardRole: Sendable, Equatable {
    /// Phone number (E.164 / digits, dashes, parens).
    case phone
    /// IMEI / serial: digits only, no autocap, no autocorrect.
    case imei
    /// Email address.
    case email
    /// URL.
    case url
    /// Search box (uses webSearch keyboard with Search return key).
    case search
    /// Generic ID/code: ASCII, no autocap/autocorrect/smart punctuation.
    case identifier
    /// Free-form prose (notes, message body) — keep autocorrect on.
    case prose
}

// MARK: - Modifier

/// Applies the §22.7 keyboard / content-type / autocorrect bundle
/// matching the supplied semantic role.
public struct FieldValidationKeyboardModifier: ViewModifier {

    public let role: FieldKeyboardRole

    public init(role: FieldKeyboardRole) {
        self.role = role
    }

    public func body(content: Content) -> some View {
        #if canImport(UIKit)
        switch role {
        case .phone:
            content
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        case .imei:
            content
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        case .email:
            content
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        case .url:
            content
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        case .search:
            content
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        case .identifier:
            content
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        case .prose:
            content
                .keyboardType(.default)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
        }
        #else
        content
        #endif
    }
}

// MARK: - View extension

public extension View {

    /// Applies the §22.7 keyboard / content-type / autocorrect bundle
    /// matching `role`.
    ///
    /// - Parameter role: The semantic role of the field.
    /// - Returns: A view with the matching `keyboardType`, `textContentType`,
    ///   capitalisation, and autocorrect settings applied.
    func brandFieldKeyboard(_ role: FieldKeyboardRole) -> some View {
        modifier(FieldValidationKeyboardModifier(role: role))
    }
}
