#if canImport(UIKit) && canImport(PencilKit)
import SwiftUI
import UIKit
import DesignSystem

// MARK: - PhotoAnnotationView binding-style entry point

/// Binding-based wrapper around ``PencilAnnotationView``.
///
/// Matches the public API contract specified in `ios/agent-ownership.md`:
/// ```swift
/// PhotoAnnotationView(image: $capturedImage)
/// ```
///
/// When the user taps Save, `image` binding is updated with the flattened result
/// and the view dismisses. When the user taps Cancel, the binding is unchanged.
///
/// iPhone: push onto a `NavigationStack` or present as a sheet.
/// iPad: same — the underlying `PencilAnnotationView` uses `Platform.isCompact`
///       to adapt the tool picker position.
public struct PhotoAnnotationBindingView: View {

    @Binding private var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    public init(image: Binding<UIImage?>) {
        self._image = image
    }

    public var body: some View {
        Group {
            if let base = image {
                PhotoAnnotationView(
                    baseImage: base,
                    onSave: { annotated in
                        image = annotated
                        dismiss()
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty state (no image set)

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No image to annotate")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("annotation.dismissEmpty")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }
}

#endif
