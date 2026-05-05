#if canImport(UIKit) && canImport(PencilKit)
import SwiftUI
import UIKit
import PencilKit
import Core
import DesignSystem

/// PencilKit overlay allowing freehand annotation (arrows, circles, highlighter)
/// on top of a captured ticket photo.
///
/// Call ``captureAnnotated()`` to flatten the base image and ink layer into a
/// single `UIImage` suitable for upload.
///
/// The `PKToolPicker` is shown on `onAppear` and hidden on `onDisappear`. On
/// Mac Catalyst / iPadOS it floats freely; on compact-width iPhone it docks at
/// the bottom of the canvas.
public struct PhotoAnnotationView: View {

    private let baseImage: UIImage
    private let onSave: (UIImage) -> Void
    private let onCancel: () -> Void

    public init(
        baseImage: UIImage,
        onSave: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.baseImage = baseImage
        self.onSave = onSave
        self.onCancel = onCancel
    }

    @StateObject private var canvasHolder = CanvasHolder()

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: baseImage)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()
            PencilCanvasRepresentable(canvasView: canvasHolder.canvas)
                .ignoresSafeArea()
        }
        .navigationTitle("Annotate Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
                .accessibilityIdentifier("annotation.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let annotated = captureAnnotated(base: baseImage, canvas: canvasHolder.canvas)
                    BrandHaptics.success()
                    onSave(annotated)
                }
                .accessibilityIdentifier("annotation.save")
                .accessibilityLabel("Save annotated photo")
            }
        }
        .onAppear {
            canvasHolder.showToolPicker()
        }
        .onDisappear {
            canvasHolder.hideToolPicker()
        }
    }

    // MARK: - Flatten

    /// Flattens base photo + ink layer into a single `UIImage`.
    public func captureAnnotated() -> UIImage {
        captureAnnotated(base: baseImage, canvas: canvasHolder.canvas)
    }

    private func captureAnnotated(base: UIImage, canvas: PKCanvasView) -> UIImage {
        let size = base.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))
            let scale = size.width / max(canvas.bounds.width, 1)
            ctx.cgContext.scaleBy(x: scale, y: scale)
            canvas.drawHierarchy(in: canvas.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - CanvasHolder

/// Observable wrapper to bridge `PKCanvasView` + `PKToolPicker` into SwiftUI state.
@MainActor
final class CanvasHolder: ObservableObject {
    let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()

    init() {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        // Default tool: ink pen
        canvas.tool = PKInkingTool(.pen, color: .systemOrange, width: 4)
    }

    func showToolPicker() {
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        canvas.becomeFirstResponder()
    }

    func hideToolPicker() {
        toolPicker.setVisible(false, forFirstResponder: canvas)
        toolPicker.removeObserver(canvas)
    }
}

// MARK: - PencilCanvasRepresentable

private struct PencilCanvasRepresentable: UIViewRepresentable {
    let canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView { canvasView }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

#endif
