#if canImport(UIKit) && canImport(PencilKit)
import SwiftUI
import PencilKit
import UIKit

/// `UIViewRepresentable` wrapping a `PKCanvasView`.
///
/// - Renders `image` as background (drawn beneath the ink layer).
/// - Propagates `PKDrawing` changes back via `Binding`.
/// - Applies `tool` (pen / marker / eraser) from the VM.
/// - Configures Apple Pencil palm rejection (`.pencilOnly` on iPad).
/// - Exposes `UndoManager` via the coordinator for VM undo/redo calls.
public struct PencilAnnotationCanvasView: UIViewRepresentable {

    public let image: UIImage?
    @Binding public var drawing: PKDrawing
    public let tool: PKTool
    /// Provide VM so coordinator can wire up `UndoManager`.
    public let viewModel: PencilAnnotationViewModel

    public init(
        image: UIImage?,
        drawing: Binding<PKDrawing>,
        tool: PKTool,
        viewModel: PencilAnnotationViewModel
    ) {
        self.image = image
        self._drawing = drawing
        self.tool = tool
        self.viewModel = viewModel
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false

        // Palm rejection: Apple Pencil only on iPad, any input on iPhone
        #if !targetEnvironment(macCatalyst)
        let idiom = UIDevice.current.userInterfaceIdiom
        canvas.drawingPolicy = (idiom == .pad) ? .pencilOnly : .anyInput
        #else
        canvas.drawingPolicy = .anyInput
        #endif

        canvas.drawing = drawing
        canvas.tool = tool
        canvas.delegate = context.coordinator

        // Wire UndoManager back to VM
        context.coordinator.wirePencilInteraction(to: canvas)

        return canvas
    }

    public func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Sync tool whenever VM changes it
        if type(of: canvas.tool) != type(of: tool) || context.coordinator.needsToolUpdate {
            canvas.tool = tool
            context.coordinator.needsToolUpdate = false
        }
        // Only push drawing when changed externally (clear/undo), not from canvas itself
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, viewModel: viewModel)
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        private var drawingBinding: Binding<PKDrawing>
        private weak var vm: PencilAnnotationViewModel?
        var needsToolUpdate: Bool = false

        init(drawing: Binding<PKDrawing>, viewModel: PencilAnnotationViewModel) {
            self.drawingBinding = drawing
            self.vm = viewModel
        }

        // MARK: PKCanvasViewDelegate

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Push new drawing up to binding/VM
            drawingBinding.wrappedValue = canvasView.drawing
            // Wire undo manager so VM can call undo()/redo()
            if let um = canvasView.undoManager {
                Task { @MainActor in
                    self.vm?.undoManager = um
                }
            }
        }

        // MARK: UIPencilInteraction (double-tap / squeeze)

        public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            Task { @MainActor in
                self.vm?.handleDoubleTap()
                self.needsToolUpdate = true
            }
        }

        @available(iOS 17.5, *)
        public func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            guard squeeze.phase == .ended else { return }
            Task { @MainActor in
                self.vm?.handleSqueeze()
            }
        }

        // MARK: Wiring

        func wirePencilInteraction(to canvas: PKCanvasView) {
            let interaction = UIPencilInteraction()
            interaction.delegate = self
            canvas.addInteraction(interaction)
        }
    }
}

// MARK: - Background image layer

/// A simple UIView that renders a UIImage scaled-to-fit, used as the
/// background layer below the PKCanvasView.
struct AnnotationBackgroundView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .black
        return iv
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = image
    }
}

#endif
