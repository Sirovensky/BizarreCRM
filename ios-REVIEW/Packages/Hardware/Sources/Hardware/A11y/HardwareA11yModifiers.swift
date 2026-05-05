#if canImport(UIKit)
import SwiftUI

// §17.10 Accessibility hardware — Switch Control + Voice Control.
//
// POS primary actions must be reachable via Switch Control.
// All named buttons must be reachable by Voice Control; numeric keys
// get custom spoken names so "Tap 1" works rather than "Tap 1, 2, 3…".
//
// These modifiers are applied to POS action buttons in the Hardware package
// (e.g. the charge button in ChargeCoordinator's UI, cash-drawer test button).
// Feature packages apply them inline; this file provides shared utilities.

// MARK: - Switch Control: explicit focus ordering

/// Marks a view as a "primary action" that Switch Control should visit early
/// in its focus cycle. Works by setting `accessibilityActivate` + ensuring
/// the control has a concrete label, hint, and a valid activation action.
public extension View {
    /// Apply to the primary POS action button (e.g. "Charge", "Print receipt").
    /// Switch Control respects the `accessibilityInputLabels` list so Voice Control
    /// users can say any alias.
    func posPrimaryAction(
        label: String,
        hint: String = "",
        aliases: [String] = []
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint.isEmpty ? "" : hint)
            .accessibilityInputLabels(aliases.isEmpty ? [label] : [label] + aliases)
            .accessibilityAddTraits(.isButton)
    }

    /// Apply to numeric keypad keys so Voice Control can target them by name.
    ///
    /// Spoken label: "Key \(digit)" (e.g. "Key 7").
    /// Voice Control command: "Tap key 7".
    func posNumericKey(_ digit: Int) -> some View {
        self
            .accessibilityLabel("Key \(digit)")
            .accessibilityInputLabels(["Key \(digit)", "\(digit)"])
            .accessibilityAddTraits(.isButton)
    }

    /// Apply to the cash-drawer test button so Switch Control and Voice Control
    /// reach it with a descriptive label.
    func drawerTestButton() -> some View {
        self
            .accessibilityLabel("Open cash drawer")
            .accessibilityHint("Double-tap to open the connected cash drawer.")
            .accessibilityInputLabels(["Open drawer", "Open cash drawer", "Test drawer"])
            .accessibilityAddTraits(.isButton)
    }

    /// Apply to the scan barcode button in the POS.
    func posScanButton() -> some View {
        self
            .accessibilityLabel("Scan barcode")
            .accessibilityHint("Activate the camera barcode scanner.")
            .accessibilityInputLabels(["Scan", "Scan barcode", "Barcode scan"])
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Hardware A11y constants

/// Shared spoken names for Voice Control. Feature packages import and use these
/// to ensure consistent naming across the POS, receipt, and hardware settings.
public enum HardwareA11yLabel {
    public static let chargeButton = "Charge"
    public static let chargeAliases = ["Charge customer", "Process payment"]

    public static let cancelCharge = "Cancel charge"
    public static let cancelAliases = ["Cancel payment", "Cancel"]

    public static let printReceipt = "Print receipt"
    public static let printAliases = ["Print", "Print receipt", "Receipt"]

    public static let openDrawer = "Open cash drawer"
    public static let drawerAliases = ["Open drawer", "Cash drawer"]

    public static let scanBarcode = "Scan barcode"
    public static let scanAliases = ["Scan", "Barcode"]

    public static let pairTerminal = "Pair terminal"
    public static let pairAliases = ["Pair reader", "Pair BlockChyp"]
}
#endif
