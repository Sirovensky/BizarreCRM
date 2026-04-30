import Foundation

/// §42.2 — Reusable helper for placing outbound calls from anywhere in the app.
///
/// Usage in a customer / ticket detail:
/// ```swift
/// Button("Call customer") {
///     CallQuickAction.placeCall(to: customer.phone)
/// }
/// ```
///
/// Does NOT require CallKit — it opens the system dialer via `tel:` URL.
public enum CallQuickAction {

    /// Strip a phone number down to digits only, then open the `tel:` URL.
    ///
    /// Cleaning rules (applied in order):
    /// 1. Remove all non-digit characters except a leading `+`.
    /// 2. Strip a leading `1` country prefix for US numbers (11-digit → 10-digit result).
    ///
    /// If the cleaned result is empty, the call is a no-op (defensive against
    /// empty strings passed from optional customer fields).
    public static func placeCall(to number: String) {
        let cleaned = cleanPhoneNumber(number)
        guard !cleaned.isEmpty,
              let url = URL(string: "tel:\(cleaned)") else { return }
#if canImport(UIKit)
        // Perform UIApplication call only on iOS/tvOS — macOS test host has no UIApplication.
        Task { @MainActor in openURLIfPossible(url) }
#endif
    }

    /// Normalize a phone number to digits only (preserving a leading `+`
    /// for international numbers). Exposed for testing.
    ///
    /// Examples:
    /// - `"(555) 123-4567"` → `"5551234567"`
    /// - `"+1-415-555-1212"` → `"+14155551212"`
    /// - `"1 (800) 555-0100"` → `"8005550100"` (leading `1` stripped from 11-digit US number)
    public static func cleanPhoneNumber(_ raw: String) -> String {
        let hasLeadingPlus = raw.hasPrefix("+")

        // Keep digits only
        var digits = raw.filter(\.isNumber)

        // Strip a leading US country code `1` only when the result would
        // otherwise be 11 digits (prevents stripping from legitimate 10-digit
        // numbers that happen to start with 1).
        if !hasLeadingPlus && digits.count == 11 && digits.hasPrefix("1") {
            digits = String(digits.dropFirst())
        }

        return hasLeadingPlus ? "+" + digits : digits
    }
}

// MARK: - UIKit shim (compiled only on platforms that have UIApplication)

#if canImport(UIKit)
import UIKit
import SwiftUI

@MainActor
private func openURLIfPossible(_ url: URL) {
    UIApplication.shared.open(url)
}

// MARK: - SwiftUI convenience modifier (§42.2)

/// A tappable phone-number chip that immediately places a call via `tel:`.
///
/// Placed directly in a customer or ticket detail view — no extra state needed.
///
/// Usage:
/// ```swift
/// PhoneCallButton(number: customer.phone, label: customer.phone)
/// ```
public struct PhoneCallButton: View {
    public let number: String
    /// Display text; defaults to the raw number if nil.
    public let label: String?
    public let font: Font

    public init(number: String, label: String? = nil, font: Font = .body) {
        self.number = number
        self.label = label
        self.font = font
    }

    public var body: some View {
        Button {
            CallQuickAction.placeCall(to: number)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill")
                    .font(font)
                    .accessibilityHidden(true)
                Text(label ?? number)
                    .font(font)
                    .underline()
            }
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call \(label ?? number)")
        .accessibilityHint("Opens the phone dialer")
        .accessibilityIdentifier("callButton.\(number)")
    }
}
#endif
