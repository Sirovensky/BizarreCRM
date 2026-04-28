import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// §26.1 — VoiceOver focus management for sheets
//
// When a sheet or modal is presented, VoiceOver should move focus to a
// meaningful first element (e.g., the sheet title or first form field) rather
// than leaving focus on the presenting button behind the sheet.
//
// This modifier uses `@AccessibilityFocusState` to programmatically move focus
// on sheet appear **only when VoiceOver is running** — it is a no-op otherwise.
// We never override the user's manually-placed focus.

// MARK: - A11ySheetFocusModifier

/// §26.1 — Moves VoiceOver focus to a tagged element when a sheet appears.
///
/// Attach to the sheet's root view and tag the element that should receive
/// initial focus with `.accessibilityFocused($isFocused)`.
///
/// Usage inside a sheet:
/// ```swift
/// struct CreateTicketSheet: View {
///     @AccessibilityFocusState private var focusTitle: Bool
///
///     var body: some View {
///         VStack {
///             Text("New Ticket")
///                 .font(.headline)
///                 .accessibilityFocused($focusTitle)
///             // … other fields
///         }
///         .a11yFocusOnAppear($focusTitle)
///     }
/// }
/// ```
public struct A11ySheetFocusModifier: ViewModifier {
    @AccessibilityFocusState private var isFocused: Bool
    private let binding: AccessibilityFocusState<Bool>.Binding

    public init(_ binding: AccessibilityFocusState<Bool>.Binding) {
        self.binding = binding
    }

    public func body(content: Content) -> some View {
        content
            .onAppear {
#if canImport(UIKit)
                guard UIAccessibility.isVoiceOverRunning else { return }
#endif
                // Brief delay so the sheet presentation animation settles
                // before we redirect focus. VoiceOver reacts oddly when focus
                // is set mid-animation.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000) // 450ms
                    binding.wrappedValue = true
                }
            }
    }
}

// MARK: - View extension

public extension View {
    /// §26.1 — Moves VoiceOver focus to a tagged element when the view appears.
    ///
    /// A no-op unless VoiceOver is currently running. Never call this on views
    /// that are always on screen — only on sheets, modals, and popovers.
    func a11yFocusOnAppear(_ binding: AccessibilityFocusState<Bool>.Binding) -> some View {
        modifier(A11ySheetFocusModifier(binding))
    }
}

// MARK: - A11yCustomActionsModifier

/// §26.1 — Exposes swipe actions as VoiceOver custom actions on a list row.
///
/// Without this modifier, swipe-to-delete and swipe-to-archive are unreachable
/// in VoiceOver. `accessibilityActions` make them discoverable via the rotor.
///
/// Usage:
/// ```swift
/// TicketRow(ticket: t)
///     .a11ySwipeActions(primary: ("Delete", { delete(t) }),
///                       secondary: ("Archive", { archive(t) }))
/// ```
public extension View {
    /// Registers a VoiceOver custom action in addition to whatever swipe
    /// actions the view already has. Safe to call unconditionally — iOS only
    /// surfaces custom actions when VoiceOver is active.
    func a11yCustomAction(label: String, handler: @escaping () -> Void) -> some View {
        accessibilityAction(named: Text(label), handler)
    }
}
