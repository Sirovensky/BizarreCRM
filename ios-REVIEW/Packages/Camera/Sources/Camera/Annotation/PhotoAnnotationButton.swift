#if canImport(UIKit) && canImport(PencilKit)
import SwiftUI
import PencilKit
import DesignSystem
import Core

/// Reusable annotation trigger button for photo cells in `TicketDetailView`.
///
/// Usage:
/// ```swift
/// PhotoAnnotationButton(image: photo) { annotated in
///     // replace photo in PhotoStore
/// }
/// ```
///
/// The button presents `PencilAnnotationView` in a full-screen cover.
public struct PhotoAnnotationButton: View {

    private let image: UIImage
    private let onSave: (UIImage) -> Void

    @State private var isPresented: Bool = false

    public init(image: UIImage, onSave: @escaping (UIImage) -> Void) {
        self.image = image
        self.onSave = onSave
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Annotate", systemImage: "pencil.tip.crop.circle")
                .font(.subheadline)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .brandGlass(.regular, in: Capsule(), interactive: true)
        .accessibilityLabel("Annotate photo")
        .accessibilityHint("Opens the annotation canvas where you can draw on this photo")
        .fullScreenCover(isPresented: $isPresented) {
            NavigationStack {
                PencilAnnotationView(
                    baseImage: image,
                    onSave: { annotated in
                        isPresented = false
                        onSave(annotated)
                    },
                    onCancel: {
                        isPresented = false
                    }
                )
            }
        }
    }
}

#endif
