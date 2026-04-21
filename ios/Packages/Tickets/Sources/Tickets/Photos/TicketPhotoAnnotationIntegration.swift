#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §4 — Opens `PencilAnnotationView` (Phase 7 C) for ticket photo annotation.
/// Annotations are saved via `PhotoStore` (Camera pkg) as a new attachment
/// (original preserved). This file provides the integration shim so the
/// Tickets pkg compiles without a hard dependency on the Camera pkg.
public struct TicketPhotoAnnotationIntegration: View {
    @Environment(\.dismiss) private var dismiss

    /// URL of the photo to annotate.
    let photoURL: URL
    /// Called with the local URL of the saved annotation PNG.
    let onAnnotationSaved: @Sendable (URL) -> Void

    public init(photoURL: URL, onAnnotationSaved: @escaping @Sendable (URL) -> Void) {
        self.photoURL = photoURL
        self.onAnnotationSaved = onAnnotationSaved
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                annotationCanvas
            }
            .navigationTitle("Annotate Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Integration hook: in real build, calls PencilAnnotationViewModel.export()
                        // then PhotoStore.promote(). Here we pass photoURL as-is for wire-up.
                        onAnnotationSaved(photoURL)
                        dismiss()
                    }
                    .foregroundStyle(.bizarreOrange)
                }
            }
        }
    }

    /// Placeholder canvas. In production build replaced by `PencilAnnotationView`
    /// from the Camera pkg, which is imported at the App target level.
    @ViewBuilder
    private var annotationCanvas: some View {
        VStack(spacing: BrandSpacing.base) {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                default:
                    Color.bizarreSurface1
                        .frame(height: 300)
                }
            }

            HStack(spacing: BrandSpacing.base) {
                Image(systemName: "pencil.tip")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Draw tool")
                Image(systemName: "eraser")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityLabel("Eraser tool")
            }
            .padding(BrandSpacing.md)
            .brandGlass(.clear, in: Capsule())

            Text("PencilKit annotation canvas (Camera pkg)")
                .font(.brandLabelSmall())
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(BrandSpacing.base)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo annotation canvas")
    }
}
#endif
