#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRegisterShortcutsExtended (§16.14 full register accelerators)

/// Extends `PosKeyboardShortcutsModifier` with the complete set of hardware-
/// keyboard accelerators defined in §16.14:
///
/// **Cart shortcuts:**
/// - ⌘N  new sale                (already in PosKeyboardShortcutsModifier)
/// - ⌘⇧N hold / park cart        (new)
/// - ⌘R  resume held             (new)
/// - ⌘+  qty +1 on focused line  (new)
/// - ⌘−  qty −1 on focused line  (new)
/// - ⌘⌫  remove focused line     (new)
/// - ⌘⇧⌫ clear cart              (already in base modifier)
///
/// **Lookup:**
/// - ⌘F  focus product search    (already in base as onBarcode; split out here)
/// - ⌘B  focus barcode input     (already in base modifier)
/// - ⌘K  customer lookup         (already in base modifier)
///
/// **Payment:**
/// - ⌘P  open payment sheet      (already in base modifier)
/// - ⌘1  select cash tender      (new)
/// - ⌘2  select card tender      (new)
/// - ⌘3  select gift card tender (new)
/// - ⌘4  select store credit     (new)
/// - ⌘⇧P split tender            (new)
///
/// **Receipt:**
/// - ⌘⇧R reprint last            (already in base as onRecall; split here)
/// - ⌘E  email receipt           (new)
/// - ⌘S  SMS receipt             (new)
///
/// **Admin:**
/// - ⌘M  manager PIN prompt      (new)
/// - ⌘⌥V void current sale       (new)
/// - ⌘⌥R open returns            (new)
///
/// **Navigation:**
/// - Tab  cycles cart → discount → tender   (standard focus; handled by accessibility engine)
/// - Arrow keys scroll catalog grid          (handled by `.focusable` + grid; documented here)
///
/// Attach with `.posRegisterShortcutsExtended(...)`.
public struct PosRegisterShortcutsExtended: ViewModifier {

    // MARK: - Action callbacks

    let onHoldCart: () -> Void
    let onResumeHeld: () -> Void
    let onQtyPlus: () -> Void
    let onQtyMinus: () -> Void
    let onRemoveLine: () -> Void
    let onFocusSearch: () -> Void
    let onSplitTender: () -> Void
    let onSelectCash: () -> Void
    let onSelectCard: () -> Void
    let onSelectGiftCard: () -> Void
    let onSelectStoreCredit: () -> Void
    let onEmailReceipt: () -> Void
    let onSMSReceipt: () -> Void
    let onManagerPin: () -> Void
    let onVoidSale: () -> Void
    let onOpenReturns: () -> Void

    // MARK: - Body

    public func body(content: Content) -> some View {
        content.background(
            Group {
                // Cart
                shortcutButton("n", mods: [.command, .shift], label: "Hold / park cart",      action: onHoldCart)
                shortcutButton("r", mods: .command,            label: "Resume held cart",      action: onResumeHeld)
                shortcutButton("+", mods: .command,            label: "Qty +1",                action: onQtyPlus)
                shortcutButton("-", mods: .command,            label: "Qty −1",                action: onQtyMinus)
                shortcutButton(.delete, mods: .command,        label: "Remove line",           action: onRemoveLine)
                // Lookup
                shortcutButton("f", mods: .command,            label: "Focus product search",  action: onFocusSearch)
                // Payment
                shortcutButton("p", mods: [.command, .shift],  label: "Split tender",          action: onSplitTender)
                shortcutButton("1", mods: .command,            label: "Select cash",           action: onSelectCash)
                shortcutButton("2", mods: .command,            label: "Select card",           action: onSelectCard)
                shortcutButton("3", mods: .command,            label: "Select gift card",      action: onSelectGiftCard)
                shortcutButton("4", mods: .command,            label: "Select store credit",   action: onSelectStoreCredit)
                // Receipt
                shortcutButton("e", mods: .command,            label: "Email receipt",         action: onEmailReceipt)
                shortcutButton("s", mods: .command,            label: "SMS receipt",           action: onSMSReceipt)
                // Admin
                shortcutButton("m", mods: .command,            label: "Manager PIN",           action: onManagerPin)
                shortcutButton("v", mods: [.command, .option], label: "Void current sale",     action: onVoidSale)
                shortcutButton("r", mods: [.command, .option], label: "Open returns",          action: onOpenReturns)
            }
        )
    }

    // MARK: - Helpers

    private func shortcutButton(
        _ key: KeyEquivalent,
        mods: EventModifiers,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            BrandHaptics.tap()
            action()
        }) {
            EmptyView()
        }
        .keyboardShortcut(key, modifiers: mods)
        .hidden()
        .accessibilityLabel(label)
        .accessibilityIdentifier("pos.kbd.\(label.lowercased().replacingOccurrences(of: " ", with: "."))")
    }

    private func shortcutButton(
        _ key: Character,
        mods: EventModifiers,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        shortcutButton(KeyEquivalent(key), mods: mods, label: label, action: action)
    }
}

// MARK: - View extension

public extension View {
    /// Attach the extended full-register keyboard shortcut set.
    /// Use alongside `posKeyboardShortcuts(...)` — the two modifiers are additive.
    func posRegisterShortcutsExtended(
        onHoldCart:         @escaping () -> Void = {},
        onResumeHeld:       @escaping () -> Void = {},
        onQtyPlus:          @escaping () -> Void = {},
        onQtyMinus:         @escaping () -> Void = {},
        onRemoveLine:       @escaping () -> Void = {},
        onFocusSearch:      @escaping () -> Void = {},
        onSplitTender:      @escaping () -> Void = {},
        onSelectCash:       @escaping () -> Void = {},
        onSelectCard:       @escaping () -> Void = {},
        onSelectGiftCard:   @escaping () -> Void = {},
        onSelectStoreCredit: @escaping () -> Void = {},
        onEmailReceipt:     @escaping () -> Void = {},
        onSMSReceipt:       @escaping () -> Void = {},
        onManagerPin:       @escaping () -> Void = {},
        onVoidSale:         @escaping () -> Void = {},
        onOpenReturns:      @escaping () -> Void = {}
    ) -> some View {
        modifier(PosRegisterShortcutsExtended(
            onHoldCart: onHoldCart,
            onResumeHeld: onResumeHeld,
            onQtyPlus: onQtyPlus,
            onQtyMinus: onQtyMinus,
            onRemoveLine: onRemoveLine,
            onFocusSearch: onFocusSearch,
            onSplitTender: onSplitTender,
            onSelectCash: onSelectCash,
            onSelectCard: onSelectCard,
            onSelectGiftCard: onSelectGiftCard,
            onSelectStoreCredit: onSelectStoreCredit,
            onEmailReceipt: onEmailReceipt,
            onSMSReceipt: onSMSReceipt,
            onManagerPin: onManagerPin,
            onVoidSale: onVoidSale,
            onOpenReturns: onOpenReturns
        ))
    }
}

// MARK: - PosRegisterShortcut metadata

/// Static metadata for the extended register shortcuts.
/// Extends `PosKeyboardShortcut` for use in the shortcuts overlay (§23.1).
public enum PosRegisterShortcut: CaseIterable, Sendable {
    // Cart
    case holdCart, resumeHeld, qtyPlus, qtyMinus, removeLine
    // Lookup
    case focusSearch
    // Payment
    case splitTender, selectCash, selectCard, selectGiftCard, selectStoreCredit
    // Receipt
    case emailReceipt, smsReceipt
    // Admin
    case managerPin, voidSale, openReturns

    public var displayTitle: String {
        switch self {
        case .holdCart:          return "Hold / park cart"
        case .resumeHeld:        return "Resume held cart"
        case .qtyPlus:           return "Qty +1"
        case .qtyMinus:          return "Qty −1"
        case .removeLine:        return "Remove line"
        case .focusSearch:       return "Focus search"
        case .splitTender:       return "Split tender"
        case .selectCash:        return "Cash tender"
        case .selectCard:        return "Card tender"
        case .selectGiftCard:    return "Gift card"
        case .selectStoreCredit: return "Store credit"
        case .emailReceipt:      return "Email receipt"
        case .smsReceipt:        return "SMS receipt"
        case .managerPin:        return "Manager PIN"
        case .voidSale:          return "Void sale"
        case .openReturns:       return "Open returns"
        }
    }

    public var displayShortcut: String {
        switch self {
        case .holdCart:          return "⌘ ⇧ N"
        case .resumeHeld:        return "⌘ R"
        case .qtyPlus:           return "⌘ +"
        case .qtyMinus:          return "⌘ −"
        case .removeLine:        return "⌘ ⌫"
        case .focusSearch:       return "⌘ F"
        case .splitTender:       return "⌘ ⇧ P"
        case .selectCash:        return "⌘ 1"
        case .selectCard:        return "⌘ 2"
        case .selectGiftCard:    return "⌘ 3"
        case .selectStoreCredit: return "⌘ 4"
        case .emailReceipt:      return "⌘ E"
        case .smsReceipt:        return "⌘ S"
        case .managerPin:        return "⌘ M"
        case .voidSale:          return "⌘ ⌥ V"
        case .openReturns:       return "⌘ ⌥ R"
        }
    }

    public var systemImage: String {
        switch self {
        case .holdCart:          return "pause.circle"
        case .resumeHeld:        return "clock.arrow.circlepath"
        case .qtyPlus:           return "plus.circle"
        case .qtyMinus:          return "minus.circle"
        case .removeLine:        return "trash"
        case .focusSearch:       return "magnifyingglass"
        case .splitTender:       return "arrow.triangle.branch"
        case .selectCash:        return "banknote.fill"
        case .selectCard:        return "creditcard.fill"
        case .selectGiftCard:    return "giftcard.fill"
        case .selectStoreCredit: return "dollarsign.circle.fill"
        case .emailReceipt:      return "envelope.fill"
        case .smsReceipt:        return "message.fill"
        case .managerPin:        return "lock.shield.fill"
        case .voidSale:          return "xmark.circle.fill"
        case .openReturns:       return "arrow.uturn.backward.circle.fill"
        }
    }
}
#endif
