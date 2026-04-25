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
/// | Shortcut | Action          |
/// |----------|-----------------|
/// | ⌘ N      | New sale / clear cart |
/// | ⌘ B      | Open barcode scanner |
/// | ⌘ P      | Tender / charge |
/// | ⌘ H      | Hold cart        |
/// | ⌘ ⇧ R    | Recall holds     |
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

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            // ⌘ N — new sale (clear cart). Mirror of toolbar "Add custom line"
            // shortcut; here it resets the sale entirely.
            .background(
                Group {
                    newSaleButton
                    barcodeButton
                    tenderButton
                    holdButton
                    recallButton
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
}

// MARK: - View extension

public extension View {
    /// Attach the standard POS keyboard shortcuts to any view.
    ///
    /// - Parameters:
    ///   - onNewSale:  ⌘ N — Start a new sale (clear cart).
    ///   - onBarcode:  ⌘ B — Open the barcode scanner sheet.
    ///   - onTender:   ⌘ P — Open the tender / charge flow.
    ///   - onHold:     ⌘ K — Hold the current cart.
    ///   - onRecall:   ⌘ ⇧ R — Recall a held cart.
    func posKeyboardShortcuts(
        onNewSale: @escaping () -> Void,
        onBarcode: @escaping () -> Void,
        onTender: @escaping () -> Void,
        onHold: @escaping () -> Void,
        onRecall: @escaping () -> Void
    ) -> some View {
        modifier(PosKeyboardShortcutsModifier(
            onNewSale: onNewSale,
            onBarcode: onBarcode,
            onTender: onTender,
            onHold: onHold,
            onRecall: onRecall
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

    public var key: Character {
        switch self {
        case .newSale: return "n"
        case .barcode: return "b"
        case .tender:  return "p"
        case .hold:    return "h"
        case .recall:  return "r"
        }
    }

    public var modifiers: EventModifiers {
        switch self {
        case .newSale, .barcode, .tender, .hold: return .command
        case .recall:                             return [.command, .shift]
        }
    }

    public var displayTitle: String {
        switch self {
        case .newSale: return "New sale"
        case .barcode: return "Scan barcode"
        case .tender:  return "Tender / charge"
        case .hold:    return "Hold cart"
        case .recall:  return "Recall hold"
        }
    }

    public var systemImage: String {
        switch self {
        case .newSale: return "plus.circle"
        case .barcode: return "barcode.viewfinder"
        case .tender:  return "creditcard"
        case .hold:    return "pause.circle"
        case .recall:  return "clock.arrow.circlepath"
        }
    }

    /// Human-readable shortcut label (e.g. "⌘ N", "⌘ ⇧ R").
    public var displayShortcut: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        parts.append(String(key).uppercased())
        return parts.joined(separator: " ")
    }
}
#endif
