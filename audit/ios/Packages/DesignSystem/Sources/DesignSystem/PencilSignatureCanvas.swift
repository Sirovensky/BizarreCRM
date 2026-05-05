#if canImport(UIKit) && canImport(PencilKit)
import SwiftUI
import UIKit
import PencilKit

// MARK: - PencilSignatureCanvas
//
// §22.2 — Apple Pencil: `PKCanvasView` on signatures.
//
// A reusable, DesignSystem-branded signature capture widget backed by
// PencilKit.  Features:
//   • Pencil-first drawing policy (`.pencilOnly` on devices that have reported
//     Apple Pencil support; `.anyInput` fallback for finger/mouse).
//   • Tool picker hidden by default — signature fields use a fixed black ink
//     pen at 3pt width, which is the standard for legally-admissible signatures.
//   • `onStrokeAdded` callback fires after every stroke so callers can enable
//     a "Clear" / "Accept" CTA without polling.
//   • `captureImage()` flattens the drawing to a `UIImage` at screen scale.
//   • Pencil Pro hover preview: on iOS 17.5+ the API surfaces `pencilHoverPose`;
//     we register a `UIPencilInteraction` delegate so future integrations can
//     read squeeze / barrel-roll gestures without modification here.
//   • `.pencilOnly` drawing policy is gated on `UIPencilInteraction.prefersPencilOnlyDrawing`
//     (iOS 17.5+) so finger-only users aren't locked out on older hardware.
//
// Usage:
// ```swift
// @State private var canvas = PKCanvasView()
// @State private var hasSig = false
//
// PencilSignatureCanvas(canvasView: $canvas, onStrokeAdded: { hasSig = true })
//     .frame(height: 160)
//     .brandSignatureFrame()
// ```

// MARK: - PencilSignatureCanvas (SwiftUI wrapper)

/// DesignSystem-branded PencilKit signature capture canvas.
///
/// - Drop-in replacement for the inline `SignatureCanvasView` used in
///   `EstimateApproveSheet` and ticket sign-off screens.
/// - Exposes `captureImage(from:)` as a static helper so callers don't need
///   to import PencilKit.
public struct PencilSignatureCanvas: UIViewRepresentable {

    @Binding public var canvasView: PKCanvasView
    public let onStrokeAdded: () -> Void

    /// Desired line width for the signature pen.  Default 3 pt matches
    /// standard legal-signature weight.
    public var penWidth: CGFloat = 3

    public init(
        canvasView: Binding<PKCanvasView>,
        onStrokeAdded: @escaping () -> Void,
        penWidth: CGFloat = 3
    ) {
        self._canvasView = canvasView
        self.onStrokeAdded = onStrokeAdded
        self.penWidth = penWidth
    }

    // MARK: UIViewRepresentable

    public func makeUIView(context: Context) -> PKCanvasView {
        let cv = canvasView
        cv.backgroundColor = .clear

        // Drawing policy: prefer Pencil-only on devices that report Pencil
        // support; fall back to anyInput so finger users aren't blocked.
        if #available(iOS 17.5, *) {
            cv.drawingPolicy = UIPencilInteraction.prefersPencilOnlyDrawing
                ? .pencilOnly
                : .anyInput
        } else {
            cv.drawingPolicy = .anyInput
        }

        // Fixed-weight black ink pen — no tool picker for signature fields.
        let ink = PKInk(.pen, color: .label)
        cv.tool = PKInkingTool(ink: ink, width: penWidth)

        cv.delegate = context.coordinator

        // Pencil Pro squeeze/barrel-roll interaction hook (iOS 17.5+).
        // The delegate is wired but currently no-op; future integrations can
        // override `PencilInteractionDelegate` without touching this file.
        if #available(iOS 17.5, *) {
            let interaction = UIPencilInteraction()
            interaction.delegate = context.coordinator
            cv.addInteraction(interaction)
        }

        cv.becomeFirstResponder()
        return cv
    }

    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Tool width may change (e.g., re-initialisation with a different penWidth).
        let ink = PKInk(.pen, color: .label)
        uiView.tool = PKInkingTool(ink: ink, width: penWidth)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onStrokeAdded: onStrokeAdded)
    }

    // MARK: - Static helpers

    /// Flatten `canvas` strokes on top of `baseImage` and return a composite
    /// `UIImage` at screen scale.  Pass `nil` for `baseImage` to get the
    /// strokes-only image (white background).
    ///
    /// - Parameters:
    ///   - baseImage: Optional background image; pass `nil` for strokes only.
    ///   - canvas:    The `PKCanvasView` whose `drawing` is rendered.
    /// - Returns: Composited `UIImage`.
    public static func captureImage(
        baseImage: UIImage? = nil,
        canvas: PKCanvasView
    ) -> UIImage {
        let bounds = canvas.bounds
        let scale  = UIScreen.main.scale

        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { ctx in
            if let base = baseImage {
                base.draw(in: bounds)
            } else {
                UIColor.white.setFill()
                ctx.fill(bounds)
            }
            let drawing = canvas.drawing.image(from: bounds, scale: scale)
            drawing.draw(in: bounds)
        }
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, PKCanvasViewDelegate {

        let onStrokeAdded: () -> Void

        init(onStrokeAdded: @escaping () -> Void) {
            self.onStrokeAdded = onStrokeAdded
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if !canvasView.drawing.strokes.isEmpty {
                onStrokeAdded()
            }
        }
    }
}

// Pencil Pro interaction (iOS 17.5+) — delegated to Coordinator.
@available(iOS 17.5, *)
extension PencilSignatureCanvas.Coordinator: UIPencilInteractionDelegate {
    public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        // Squeeze: could open an "Erase last stroke" affordance in a future
        // iteration.  Currently a no-op so existing callers compile cleanly.
    }
}

// MARK: - View modifier helper

public extension View {
    /// Applies the standard brand border + background for a signature canvas.
    ///
    /// Convenience so every signature field looks identical without each
    /// call site duplicating the overlay/background chain.
    func brandSignatureFrame(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 1)
            )
            .accessibilityLabel("Signature canvas. Draw signature here.")
    }
}

#endif
