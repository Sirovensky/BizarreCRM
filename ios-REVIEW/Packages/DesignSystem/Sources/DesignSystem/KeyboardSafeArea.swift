import SwiftUI

// §22.7 — Safe area: keyboard avoidance for forms with bottom-anchored
// primary actions.
//
// Rule (from ActionPlan §22, line 3709):
//   - Default: let SwiftUI scroll views adjust for the keyboard naturally.
//   - Do NOT add .ignoresSafeArea(.keyboard) to containers that hold user
//     input — it causes content to slide under the software keyboard.
//   - DO use .safeAreaInset(edge: .bottom) to keep floating bottom-anchored
//     buttons (Save / Confirm) visible above the keyboard frame.
//
// Usage — floating action button pattern:
//   ScrollView {
//       FormContent()
//   }
//   .keyboardSafeBottomAction {
//       SaveButton()
//   }

// MARK: - View extension

public extension View {

    /// Pins an action view to the bottom of the receiver, above the
    /// software keyboard, using `safeAreaInset(edge: .bottom)`.
    ///
    /// Use this for views that have a floating primary action button
    /// (not toolbar-based) that must remain visible when the keyboard
    /// appears.
    ///
    /// - Parameter content: The view to pin above the keyboard. Typically
    ///   a full-width `Button` with `.borderedProminent` style.
    /// - Returns: A view with the action pinned above the keyboard inset.
    func keyboardSafeBottomAction<Action: View>(
        @ViewBuilder action: () -> Action
    ) -> some View {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            action()
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
                .background(.regularMaterial)
        }
    }
}
