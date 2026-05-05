import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// §26.1 — SheetFocusModifier
// Moves VoiceOver focus to a nominated element when a sheet opens.
// When VoiceOver is off the modifier is a silent no-op — the
// `@AccessibilityFocusState` binding is simply never triggered.

// MARK: - focusOnSheetAppear

/// Moves VoiceOver focus to this view when the sheet appears, if VoiceOver
/// is currently running. Ignored when VoiceOver is off.
///
/// Attach to the primary element inside a `.sheet` or `.fullScreenCover`
/// that should receive VoiceOver cursor on first appearance:
///
/// ```swift
/// .sheet(isPresented: $showCreate) {
///     VStack {
///         Text("New Ticket")
///             .font(.brandTitleLarge())
///             .focusOnSheetAppear()     // ← VoiceOver lands here
///         // …
///     }
/// }
/// ```
///
/// Implementation: uses `@AccessibilityFocusState` internally. The binding
/// is set after a short delay so the sheet animation settles before the
/// focus jump, preventing "cursor teleport" artifacts in VoiceOver.
public extension View {
    func focusOnSheetAppear() -> some View {
        modifier(SheetFocusModifier())
    }
}

// MARK: - SheetFocusModifier

private struct SheetFocusModifier: ViewModifier {
    @AccessibilityFocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($isFocused)
            .onAppear {
                // Only drive focus when VoiceOver is active. The flag is read
                // lazily at onAppear time so sheets that appear before VoiceOver
                // is toggled on aren't affected.
                #if canImport(UIKit)
                guard UIAccessibility.isVoiceOverRunning else { return }
                #else
                return
                #endif
                // Small delay lets the sheet present and settle so VoiceOver
                // doesn't announce an element that is still mid-animation.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000) // 0.35 s
                    isFocused = true
                }
            }
    }
}
