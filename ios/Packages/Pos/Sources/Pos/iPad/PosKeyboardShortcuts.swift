#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// Registers iPad hardware-keyboard shortcuts for the POS register.
///
/// Attach to any view in the POS hierarchy with `.posKeyboardShortcuts(...)`.
/// The modifier installs `.keyboardShortcut` commands that fire even when
/// no button has focus — the system routes them via the responder chain while
/// the view is on screen.
///
/// | Shortcut | Action                  |
/// |----------|-------------------------|
/// | ⌘ N      | New sale / clear cart   |
/// | ⌘ B      | Open barcode scanner    |
/// | ⌘ P      | Tender / charge         |
/// | ⌘ H      | Hold cart               |
/// | ⌘ ⇧ R    | Recall holds            |
/// | ⌘ K      | Attach customer         |
/// | ⌘ ⇧ D    | Cart discount           |
/// | ⌘ ⇧ T    | Add tip                 |
/// | ⌘ ⇧ F    | Add fee                 |
/// | ⌘ ⇧ ⌫   | Clear cart              |
///
/// These match the menu items already wired in `PosView.posToolbar` so
/// the keyboard accelerators work both from the hardware keyboard and the
/// toolbar overflow menu.
public struct PosKeyboardShortcutsModifier: ViewModifier {

    // MARK: - Actions

    let onNewSale: () -> Void
    let onBarcode: () -> Void
    let onTender: () -> Void
    let onHold: () -> Void
    let onRecall: () -> Void
    let onCustomer: () -> Void
    let onDiscount: () -> Void
    let onTip: () -> Void
    let onFee: () -> Void
    let onClear: () -> Void

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .background(
                Group {
                    newSaleButton
                    barcodeButton
                    tenderButton
                    holdButton
                    recallButton
                    customerButton
                    discountButton
                    tipButton
                    feeButton
                    clearButton
                }
            )
    }

    // MARK: - Hidden keyboard-shortcut buttons
    //
    // SwiftUI .keyboardShortcut must be attached to a Button or a view with
    // a Button somewhere in its body to be picked up by the system. We place
    // zero-size hidden buttons in a background so they participate in the
    // responder chain without taking layout space.

    private var newSaleButton: some View {
        Button(action: {
            BrandHaptics.tap()
            onNewSale()
        }) {
            EmptyView()
        }
        .keyboardShortcut("n", modifiers: .command)
        .hidden()
        .accessibilityLabel("New sale")
        .accessibilityIdentifier("pos.keyboard.newSale")
    }

    private var barcodeButton: some View {
        Button(action: {
            BrandHaptics.tap()
            onBarcode()
        }) {
            EmptyView()
        }
        .keyboardShortcut("b", modifiers: .command)
        .hidden()
        .accessibilityLabel("Open barcode scanner")
        .accessibilityIdentifier("pos.keyboard.barcode")
    }

    private var tenderButton: some View {
        Button(action: {
            BrandHaptics.tapMedium()
            onTender()
        }) {
            EmptyView()
        }
        .keyboardShortcut("p", modifiers: .command)
        .hidden()
        .accessibilityLabel("Tender cart")
        .accessibilityIdentifier("pos.keyboard.tender")
    }

    private var holdButton: some View {
        Button(action: {
            BrandHaptics.tap()
            onHold()
        }) {
            EmptyView()
        }
        .keyboardShortcut("h", modifiers: .command)
        .hidden()
        .accessibilityLabel("Hold cart")
        .accessibilityIdentifier("pos.keyboard.hold")
    }

    private var recallButton: some View {
        Button(action: {
            BrandHaptics.tap()
            onRecall()
        }) {
            EmptyView()
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .hidden()
        .accessibilityLabel("Recall held cart")
        .accessibilityIdentifier("pos.keyboard.recall")
    }

    private var customerButton: some View {
        Button(action: {
            BrandHaptics.tap()
            onCustomer()
        }) {
            EmptyView()
        }
        .keyboardShortcut("k", modifiers: .command)
        .hidden()
        .accessibilityLabel("Attach customer")
        .accessibilityIdentifier("pos.keyboard.customer")
    }

    private var discountButton: some View {
        Button(action: {
            BrandHaptics.tap()
            onDiscount()
        }) {
            EmptyView()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .hidden()
        .accessibilityLabel("Cart discount")
        .accessibilityIdentifier("pos.keyboard.discount")
    }

    private var tipButton: some View {
        Button(action: {
            BrandHaptics.tap()
            onTip()
        }) {
            EmptyView()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .hidden()
        .accessibilityLabel("Add tip")
        .accessibilityIdentifier("pos.keyboard.tip")
    }

    private var feeButton: some View {
        Button(action: {
            BrandHaptics.tap()
            onFee()
        }) {
            EmptyView()
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .hidden()
        .accessibilityLabel("Add fee")
        .accessibilityIdentifier("pos.keyboard.fee")
    }

    private var clearButton: some View {
        Button(action: {
            BrandHaptics.tapMedium()
            onClear()
        }) {
            EmptyView()
        }
        .keyboardShortcut(.delete, modifiers: [.command, .shift])
        .hidden()
        .accessibilityLabel("Clear cart")
        .accessibilityIdentifier("pos.keyboard.clear")
    }
}

// MARK: - View extension

public extension View {
    /// Attach the standard POS keyboard shortcuts to any view.
    ///
    /// - Parameters:
    ///   - onNewSale:  ⌘ N — Start a new sale (same as clear, resets cart + begins fresh).
    ///   - onBarcode:  ⌘ B — Open the barcode scanner sheet.
    ///   - onTender:   ⌘ P — Open the tender / charge flow.
    ///   - onHold:     ⌘ H — Hold the current cart.
    ///   - onRecall:   ⌘ ⇧ R — Recall a held cart.
    ///   - onCustomer: ⌘ K — Open the customer picker / attach a customer.
    ///   - onDiscount: ⌘ ⇧ D — Open the cart discount sheet.
    ///   - onTip:      ⌘ ⇧ T — Open the tip sheet.
    ///   - onFee:      ⌘ ⇧ F — Open the fee sheet.
    ///   - onClear:    ⌘ ⇧ ⌫ — Clear the cart (destructive, no hold saved).
    func posKeyboardShortcuts(
        onNewSale: @escaping () -> Void,
        onBarcode: @escaping () -> Void,
        onTender: @escaping () -> Void,
        onHold: @escaping () -> Void,
        onRecall: @escaping () -> Void,
        onCustomer: @escaping () -> Void = {},
        onDiscount: @escaping () -> Void = {},
        onTip: @escaping () -> Void = {},
        onFee: @escaping () -> Void = {},
        onClear: @escaping () -> Void = {}
    ) -> some View {
        modifier(PosKeyboardShortcutsModifier(
            onNewSale: onNewSale,
            onBarcode: onBarcode,
            onTender: onTender,
            onHold: onHold,
            onRecall: onRecall,
            onCustomer: onCustomer,
            onDiscount: onDiscount,
            onTip: onTip,
            onFee: onFee,
            onClear: onClear
        ))
    }
}

// MARK: - Shortcut metadata

/// Static metadata for each POS keyboard shortcut. Useful for building
/// contextual help overlays and accessibility descriptions without
/// re-listing them by hand.
public enum PosKeyboardShortcut: CaseIterable, Sendable {
    case newSale
    case barcode
    case tender
    case hold
    case recall
    case customer
    case discount
    case tip
    case fee
    case clear

    public var key: Character {
        switch self {
        case .newSale:  return "n"
        case .barcode:  return "b"
        case .tender:   return "p"
        case .hold:     return "h"
        case .recall:   return "r"
        case .customer: return "k"
        case .discount: return "d"
        case .tip:      return "t"
        case .fee:      return "f"
        case .clear:    return "\u{08}" // backspace/delete
        }
    }

    public var modifiers: EventModifiers {
        switch self {
        case .newSale, .barcode, .tender, .hold, .customer: return .command
        case .recall, .discount, .tip, .fee, .clear: return [.command, .shift]
        }
    }

    public var displayTitle: String {
        switch self {
        case .newSale:  return "New sale"
        case .barcode:  return "Scan barcode"
        case .tender:   return "Tender / charge"
        case .hold:     return "Hold cart"
        case .recall:   return "Recall hold"
        case .customer: return "Attach customer"
        case .discount: return "Cart discount"
        case .tip:      return "Add tip"
        case .fee:      return "Add fee"
        case .clear:    return "Clear cart"
        }
    }

    public var systemImage: String {
        switch self {
        case .newSale:  return "plus.circle"
        case .barcode:  return "barcode.viewfinder"
        case .tender:   return "creditcard"
        case .hold:     return "pause.circle"
        case .recall:   return "clock.arrow.circlepath"
        case .customer: return "person.badge.plus"
        case .discount: return "tag"
        case .tip:      return "hand.thumbsup"
        case .fee:      return "plus.forwardslash.minus"
        case .clear:    return "trash"
        }
    }

    /// Human-readable shortcut label (e.g. "⌘ N", "⌘ ⇧ R").
    public var displayShortcut: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if key == "\u{08}" {
            parts.append("⌫")
        } else {
            parts.append(String(key).uppercased())
        }
        return parts.joined(separator: " ")
    }
}
#endif
