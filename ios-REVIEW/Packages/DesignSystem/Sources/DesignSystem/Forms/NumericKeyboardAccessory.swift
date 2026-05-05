#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - NumericKeyboardAccessoryModifier
//
// §22.7 — Accessory toolbar for numeric fields.
//
// SwiftUI's `.keyboardType(.decimalPad)` and `.numberPad` show the system
// numeric keypad which lacks a `$` / `%` key, has no Done button, and offers
// no Next/Prev focus traversal. This modifier attaches a `UIToolbar` accessory
// above the keyboard with:
//
//   [ $ ] [ % ]                 ← prepend tokens at caret (money fields)
//                  [‹] [›]      ← prev / next focus traversal
//                       [ Done ] ← dismiss keyboard
//
// Usage:
//   TextField("Amount", text: $amountText)
//       .keyboardType(.decimalPad)
//       .focused($focus, equals: .amount)
//       .brandNumericKeyboardAccessory(
//           focus: $focus,
//           current: .amount,
//           prev: .description,
//           next: .quantity,
//           insertSymbol: { $amountText.wrappedValue += $0 }
//       )
//
// The toolbar auto-hides when a hardware keyboard is attached (iPadOS / Mac
// Designed-for-iPad) since arrow keys + Tab handle traversal natively and
// the on-screen keyboard isn't visible.

public extension View {
    /// Attach a numeric-keypad accessory toolbar with $ / %, prev / next
    /// focus traversal, and Done.
    ///
    /// - Parameters:
    ///   - focus: A `FocusState.Binding` shared across the whole form.
    ///   - current: The field identity this modifier is attached to.
    ///   - prev:    The field to focus when ‹ is tapped, or `nil` to disable.
    ///   - next:    The field to focus when › is tapped, or `nil` to disable.
    ///   - showSymbols: Show `$` / `%` insert buttons (money fields). Default `true`.
    ///   - insertSymbol: Closure invoked with the tapped symbol so the caller
    ///     can append it to the bound text. Pass `nil` to hide the buttons.
    func brandNumericKeyboardAccessory<Field: Hashable>(
        focus: FocusState<Field?>.Binding,
        current: Field,
        prev: Field? = nil,
        next: Field? = nil,
        showSymbols: Bool = true,
        insertSymbol: ((String) -> Void)? = nil
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focus.wrappedValue == current {
                    if showSymbols, let insert = insertSymbol {
                        Button("$") { insert("$") }
                            .accessibilityLabel("Insert dollar sign")
                            .font(.brandLabelLarge())
                        Button("%") { insert("%") }
                            .accessibilityLabel("Insert percent sign")
                            .font(.brandLabelLarge())
                    }
                    Spacer()
                    Button {
                        if let p = prev { focus.wrappedValue = p }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .accessibilityLabel("Previous field")
                    .disabled(prev == nil)
                    Button {
                        if let n = next { focus.wrappedValue = n }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Next field")
                    .disabled(next == nil)
                    Button("Done") {
                        focus.wrappedValue = nil
                    }
                    .font(.brandLabelLarge())
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
        }
    }
}
#endif
