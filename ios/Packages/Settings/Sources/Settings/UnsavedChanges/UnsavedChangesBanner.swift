import SwiftUI
import DesignSystem

// MARK: - UnsavedChangesBanner (§19.0)
//
// Sticky glass footer shown when any Settings tab form is dirty.
// Usage: wrap a settings detail page with `.unsavedChangesBanner(isDirty:onSave:onDiscard:)`.
//
// The banner sticks to the bottom of the view above the home indicator via
// `.safeAreaInset(edge: .bottom)`.

/// Sticky "Save / Discard" glass footer for Settings forms.
public struct UnsavedChangesBanner: View {
    public let onSave: () -> Void
    public let onDiscard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onSave: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        self.onSave = onSave
        self.onDiscard = onDiscard
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            Text("You have unsaved changes.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Discard") {
                BrandHaptics.selection()
                onDiscard()
            }
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .buttonStyle(.plain)
            .accessibilityHint("Discard unsaved changes")

            Button("Save") {
                BrandHaptics.success()
                onSave()
            }
            .font(.brandBodyLarge().bold())
            .foregroundStyle(.bizarreOrange)
            .buttonStyle(.plain)
            .accessibilityHint("Save changes")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unsaved changes")
    }
}

// MARK: - View modifier

private struct UnsavedChangesBannerModifier: ViewModifier {
    let isDirty: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isDirty {
                    UnsavedChangesBanner(onSave: onSave, onDiscard: onDiscard)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                )
                        )
                }
            }
            .animation(BrandMotion.snappy, value: isDirty)
    }
}

public extension View {
    /// Attaches a sticky "Save / Discard" glass footer when `isDirty` is true.
    ///
    /// - Parameters:
    ///   - isDirty: Binding to the form's dirty state.
    ///   - onSave: Called when the user taps "Save".
    ///   - onDiscard: Called when the user taps "Discard". You are responsible for
    ///     resetting the form state and clearing `isDirty`.
    func unsavedChangesBanner(
        isDirty: Bool,
        onSave: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) -> some View {
        modifier(UnsavedChangesBannerModifier(isDirty: isDirty, onSave: onSave, onDiscard: onDiscard))
    }
}
