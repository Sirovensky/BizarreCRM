import SwiftUI
import DesignSystem

// MARK: - UnsavedChangesBanner
//
// §19.0 — Sticky glass footer with "Save" / "Discard" shown whenever a
// Settings page form is dirty.
//
// Usage: add `.unsavedChangesBanner(isDirty:, onSave:, onDiscard:)` to
// any Settings page view. The banner slides in from the bottom when
// `isDirty` becomes true and slides out when cleared.
//
// Liquid Glass: banner is chrome (nav chrome category per CLAUDE.md §Liquid Glass).
// Content rows never receive glass — only this chrome footer.

public struct UnsavedChangesBanner: View {

    public let onSave: () async -> Void
    public let onDiscard: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSaving: Bool = false

    public init(onSave: @escaping () async -> Void, onDiscard: @escaping () -> Void) {
        self.onSave = onSave
        self.onDiscard = onDiscard
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Button("Discard") {
                onDiscard()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityLabel("Discard unsaved changes")
            .accessibilityIdentifier("settings.unsaved.discard")

            Spacer()

            Text("Unsaved changes")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Spacer()

            Button {
                isSaving = true
                Task {
                    await onSave()
                    isSaving = false
                }
            } label: {
                HStack(spacing: BrandSpacing.xs) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .accessibilityLabel("Saving")
                    }
                    Text("Save")
                        .font(.brandBodyMedium().bold())
                }
            }
            .disabled(isSaving)
            .buttonStyle(.plain)
            .foregroundStyle(.bizarreOrange)
            .accessibilityLabel(isSaving ? "Saving changes" : "Save changes")
            .accessibilityIdentifier("settings.unsaved.save")
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.regular, in: Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unsaved changes")
    }
}

// MARK: - View modifier

public struct UnsavedChangesBannerModifier: ViewModifier {
    public let isDirty: Bool
    public let onSave: () async -> Void
    public let onDiscard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isDirty {
                    UnsavedChangesBanner(onSave: onSave, onDiscard: onDiscard)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85),
                value: isDirty
            )
    }
}

public extension View {
    /// Adds the §19.0 unsaved-changes sticky glass footer when `isDirty` is true.
    func unsavedChangesBanner(
        isDirty: Bool,
        onSave: @escaping () async -> Void,
        onDiscard: @escaping () -> Void
    ) -> some View {
        modifier(UnsavedChangesBannerModifier(isDirty: isDirty, onSave: onSave, onDiscard: onDiscard))
    }
}
