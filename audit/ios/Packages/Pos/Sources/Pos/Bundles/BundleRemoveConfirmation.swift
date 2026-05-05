#if canImport(UIKit)
import SwiftUI
import Core

// MARK: - BundleRemoveConfirmation
//
// Action-sheet helper that asks "Remove paired parts too?" when the cashier
// attempts to remove a service line that has bundled children.
//
// Spec: docs/pos-redesign-plan.md §4.7
//       docs/pos-implementation-wave.md §Agent F

// MARK: - RemoveMode

/// Decision produced by the "Remove paired parts?" action sheet.
public enum RemoveMode: Equatable, Sendable {
    /// Remove the service line AND all paired children (default Yes).
    case cascade
    /// Remove the service line only; leave children in the cart.
    case serviceOnly
}

// MARK: - BundleRemoveConfirmationModifier

/// View modifier that presents an action sheet when `isPresented` is `true`
/// and calls `onDecision` with the cashier's choice.
///
/// Usage:
/// ```swift
/// someView
///     .bundleRemoveConfirmation(
///         isPresented: $showConfirm,
///         childCount: 2
///     ) { mode in
///         if mode == .cascade { cart.removeBundle(bundleId: id) }
///         else { cart.removeLine(id: serviceLineId) }
///     }
/// ```
public struct BundleRemoveConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let childCount: Int
    let onDecision: (RemoveMode) -> Void

    public func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove service line?",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                // Default (highlighted) action: cascade removal.
                Button(
                    childCount == 1
                        ? "Remove service + 1 paired part"
                        : "Remove service + \(childCount) paired parts",
                    role: .destructive
                ) {
                    onDecision(.cascade)
                }
                .accessibilityLabel(
                    "Remove service line and all \(childCount) paired parts"
                )

                Button("Remove service line only") {
                    onDecision(.serviceOnly)
                }
                .accessibilityLabel("Remove only the service line, keep parts")

                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
            } message: {
                Text(
                    childCount == 1
                        ? "This service has 1 paired part in the cart. Remove it too?"
                        : "This service has \(childCount) paired parts in the cart. Remove them too?"
                )
            }
    }
}

public extension View {
    /// Attaches the bundle-remove action sheet.
    ///
    /// - Parameters:
    ///   - isPresented: Binding that triggers the sheet.
    ///   - childCount:  Number of paired children (drives message copy).
    ///   - onDecision:  Called with `.cascade` or `.serviceOnly`.
    func bundleRemoveConfirmation(
        isPresented: Binding<Bool>,
        childCount: Int,
        onDecision: @escaping (RemoveMode) -> Void
    ) -> some View {
        modifier(
            BundleRemoveConfirmationModifier(
                isPresented: isPresented,
                childCount: childCount,
                onDecision: onDecision
            )
        )
    }
}
#endif
