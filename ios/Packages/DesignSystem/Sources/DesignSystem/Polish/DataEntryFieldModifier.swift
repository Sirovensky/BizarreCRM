import SwiftUI

// §22 (line 3686) — Autocorrect / SmartDashes / SmartQuotes off for data-entry
// fields (IDs, codes, IMEI, email, URL). On for free-form prose (notes, SMS).
//
// Centralising the toggle prevents the easy mistake of leaving SmartQuotes on
// for an IMEI input — ⌘⇧' produces a curly quote, breaking server validation.
//
// Usage:
//   TextField("IMEI", text: $imei)
//       .dataEntryField(.identifier)
//
//   TextField("Email", text: $email)
//       .dataEntryField(.email)
//
//   TextEditor(text: $notes)
//       .dataEntryField(.prose)

public enum DataEntryKind: Sendable {
    /// IDs / SKUs / IMEI / serial — no autocorrect, no smart punctuation.
    case identifier
    /// Email — `.emailAddress` keyboard, no autocorrect.
    case email
    /// URL — `.URL` keyboard, no autocorrect.
    case url
    /// Numeric — `.numberPad` keyboard.
    case number
    /// Phone — `.phonePad`, no autocorrect.
    case phone
    /// Free-form prose: notes, SMS, message body. Autocorrect on, smart on.
    case prose
}

public struct DataEntryFieldModifier: ViewModifier {
    private let kind: DataEntryKind

    public init(_ kind: DataEntryKind) {
        self.kind = kind
    }

    public func body(content: Content) -> some View {
        #if canImport(UIKit)
        switch kind {
        case .identifier:
            content
                .keyboardType(.asciiCapable)
                .textContentType(nil)
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
        case .number:
            content
                .keyboardType(.numberPad)
                .autocorrectionDisabled(true)
        case .phone:
            content
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .autocorrectionDisabled(true)
        case .prose:
            content
                .keyboardType(.default)
                .autocorrectionDisabled(false)
        }
        #else
        content
        #endif
    }
}

public extension View {
    /// Apply input semantics for a typed data-entry field.
    ///
    /// Identifiers / emails / URLs / numbers / phones get the right keyboard,
    /// content type, capitalisation, and autocorrect/smart-punctuation off.
    /// Prose enables autocorrect.
    func dataEntryField(_ kind: DataEntryKind) -> some View {
        modifier(DataEntryFieldModifier(kind))
    }
}
