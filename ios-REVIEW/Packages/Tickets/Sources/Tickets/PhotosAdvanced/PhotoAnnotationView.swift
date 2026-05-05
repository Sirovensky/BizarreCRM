#if canImport(UIKit)
import SwiftUI
import PencilKit
import Core
import DesignSystem

// MARK: - Annotation result

public struct PhotoAnnotationResult: Sendable {
    /// PNG data of the photo composited with the PencilKit drawing on top.
    public let compositedPNG: Data
}

// MARK: - View

/// Full-screen PencilKit overlay for drawing annotations on a ticket photo.
/// The original image is displayed beneath a transparent `PKCanvasView`.
/// On "Save" the drawing is composited onto the image and returned via `onSave`.
/// Liquid Glass used only on toolbar / chrome, not on canvas content.
@MainActor
public struct PhotoAnnotationView: View {

    // MARK: Init

    let photo: UIImage
    let onSave: @MainActor (PhotoAnnotationResult) -> Void
    let onCancel: @MainActor () -> Void

    public init(
        photo: UIImage,
        onSave: @escaping @MainActor (PhotoAnnotationResult) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.photo = photo
        self.onSave = onSave
        self.onCancel = onCancel
    }

    // MARK: State

    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                photoLayer
                canvasLayer
                if isSaving {
                    savingOverlay
                }
                if let msg = errorMessage {
                    errorBanner(msg)
                }
            }
            .navigationTitle("Annotate Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    cancelButton
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
                ToolbarItem(placement: .bottomBar) {
                    clearButton
                }
            }
        }
        .onAppear { configureCanvas() }
    }

    // MARK: - Layers

    private var photoLayer: some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFit()
            .ignoresSafeArea(edges: .horizontal)
            .accessibilityHidden(true)
    }

    private var canvasLayer: some View {
        AnnotationCanvasRepresentable(
            canvasView: $canvasView,
            toolPicker: toolPicker
        )
        .ignoresSafeArea()
        .accessibilityLabel("Annotation drawing canvas")
        .accessibilityHint("Use Apple Pencil or finger to annotate the photo")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    // MARK: - Toolbar items

    private var cancelButton: some View {
        Button("Cancel") {
            onCancel()
        }
        .foregroundStyle(.white)
        .accessibilityLabel("Cancel annotation")
    }

    private var saveButton: some View {
        Button("Save") {
            saveAnnotation()
        }
        .foregroundStyle(.bizarreOrange)
        .disabled(isSaving)
        .accessibilityLabel("Save annotated photo")
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            canvasView.drawing = PKDrawing()
        } label: {
            Label("Clear", systemImage: "trash")
                .foregroundStyle(.white.opacity(0.8))
        }
        .accessibilityLabel("Clear all annotations")
    }

    // MARK: - Overlays

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            ProgressView("Saving…")
                .foregroundStyle(.white)
                .padding(BrandSpacing.lg)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saving annotation")
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
            }
            .padding(BrandSpacing.base)
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            .padding(BrandSpacing.base)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(msg)")
    }

    // MARK: - Canvas setup

    private func configureCanvas() {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
    }

    // MARK: - Compositing

    private func saveAnnotation() {
        isSaving = true
        errorMessage = nil

        let drawing = canvasView.drawing
        let targetSize = photo.size
        let scale = photo.scale

        // Composite on a background Task to avoid blocking the main thread
        // while still dispatching the result callback on main actor.
        Task.detached(priority: .userInitiated) {
            let result = await MainActor.run {
                compositeDrawingOnPhoto(drawing: drawing, size: targetSize, scale: scale)
            }
            await MainActor.run {
                isSaving = false
                switch result {
                case .success(let pngData):
                    onSave(PhotoAnnotationResult(compositedPNG: pngData))
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func compositeDrawingOnPhoto(
        drawing: PKDrawing,
        size: CGSize,
        scale: CGFloat
    ) -> Result<Data, AnnotationError> {
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = scale
            return fmt
        }())
        let composited = renderer.image { ctx in
            photo.draw(in: CGRect(origin: .zero, size: size))
            let drawingImage = drawing.image(
                from: CGRect(origin: .zero, size: size),
                scale: scale
            )
            drawingImage.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = composited.pngData() else {
            return .failure(.renderFailed)
        }
        return .success(png)
    }
}

// MARK: - UIViewRepresentable

private struct AnnotationCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let toolPicker: PKToolPicker

    func makeUIView(context: Context) -> PKCanvasView { canvasView }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

// MARK: - Errors

public enum AnnotationError: LocalizedError {
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .renderFailed: return "Could not render the annotated image."
        }
    }
}

#endif
