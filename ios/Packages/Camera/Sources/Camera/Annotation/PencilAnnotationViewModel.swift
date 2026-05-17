#if canImport(UIKit) && canImport(PencilKit)
import Observation
import PencilKit
import SwiftUI
import UIKit
import Core

/// @MainActor observable VM for pencil annotation state.
/// Owns the PKDrawing, active tool, color and thickness.
/// Tests can drive it without UIKit canvas references.
@Observable
@MainActor
public final class PencilAnnotationViewModel {

    // MARK: - Drawing state

    public var currentDrawing: PKDrawing = PKDrawing()
    public var activeTool: AnnotationTool = .pen
    public var activeColor: AnnotationPresetColor = .orange
    public var activeThickness: Double = 4.0

    // MARK: - UI toggles

    public var isToolPickerVisible: Bool = true

    // MARK: - Derived

    /// The resolved PKTool for the canvas.
    public var resolvedPKTool: PKTool {
        activeTool.pkTool(color: activeColor.uiColor, width: CGFloat(activeThickness))
    }

    // MARK: - Background image

    private let backgroundImage: UIImage?

    public init(backgroundImage: UIImage? = nil) {
        self.backgroundImage = backgroundImage
    }

    // MARK: - Undo / Redo

    /// Called by the canvas via `UndoManager`.
    /// Forwarded from the canvas coordinator — stored as a weak ref.
    weak var undoManager: UndoManager?

    public func undo() {
        undoManager?.undo()
    }

    public func redo() {
        undoManager?.redo()
    }

    public func clear() {
        currentDrawing = PKDrawing()
    }

    // MARK: - Tool switching (Pencil double-tap / squeeze)

    /// Cycles to the next non-eraser ink tool, honoring UIPencilPreferredAction.
    /// Shape tools (arrow/rectangle/oval/textBox) are skipped by double-tap.
    public func handleDoubleTap() {
        let drawingTools: [AnnotationTool] = [.pen, .highlighter, .marker]
        guard let idx = drawingTools.firstIndex(of: activeTool) else {
            // Currently on eraser or shape tool — go back to pen
            activeTool = .pen
            return
        }
        activeTool = drawingTools[(idx + 1) % drawingTools.count]
    }

    /// Pencil Pro squeeze — toggle tool picker visibility.
    public func handleSqueeze() {
        isToolPickerVisible.toggle()
    }

    // MARK: - Export

    /// Flattens drawing + background into a single `UIImage`.
    public func exportFlattened() async -> UIImage? {
        let drawing = currentDrawing
        let background = backgroundImage
        // BUGHUNT-2026-05-17: capture UIScreen.main.scale on the main actor
        // BEFORE jumping to Task.detached. UIScreen.main must only be read
        // from the main thread; reading it from the detached worker is
        // undefined behavior (Swift 6 main-actor isolation makes this a
        // hard error in strict-concurrency builds, and it can crash
        // legitimately at runtime on iOS 17+).
        let screenScale = UIScreen.main.scale
        return await Task.detached(priority: .userInitiated) {
            let size: CGSize
            if let bg = background {
                size = bg.size
            } else {
                // Fallback: use drawing bounds or a safe default
                let drawingBounds = drawing.bounds
                size = drawingBounds.isEmpty
                    ? CGSize(width: 1024, height: 768)
                    : drawingBounds.size
            }
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                if let bg = background {
                    bg.draw(in: CGRect(origin: .zero, size: size))
                } else {
                    UIColor.black.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                }
                let scale = size.width / max(size.width, 1)
                ctx.cgContext.scaleBy(x: scale, y: scale)
                let inkImage = drawing.image(from: CGRect(origin: .zero, size: size),
                                             scale: screenScale)
                inkImage.draw(in: CGRect(origin: .zero, size: size))
            }
        }.value
    }

    /// Saves the flattened image to a `PhotoStore`.
    public func saveToPhotoStore(store: PhotoStore) async throws {
        guard let flattened = await exportFlattened() else {
            throw AnnotationError.flattenFailed
        }
        guard let jpeg = flattened.jpegData(compressionQuality: 0.85) else {
            throw AnnotationError.encodingFailed
        }
        let staged = try await store.stage(data: jpeg)
        AppLog.ui.info("PencilAnnotation: saved to PhotoStore at \(staged.lastPathComponent, privacy: .public)")
    }

    // MARK: - Stroke count (for accessibility)

    public var strokeCount: Int { currentDrawing.strokes.count }
}

// MARK: - Errors

public enum AnnotationError: Error, Sendable {
    case flattenFailed
    case encodingFailed
}

#endif
