#if canImport(UIKit) && canImport(PencilKit)
import SwiftUI
import PencilKit
import DesignSystem
import Core

/// Full annotation screen: canvas + floating tool picker.
///
/// Push onto a `NavigationStack` via `PhotoAnnotationButton` or directly.
/// On save, calls `onSave` with the flattened `UIImage`.
public struct PencilAnnotationView: View {

    private let baseImage: UIImage
    private let onSave: (UIImage) -> Void
    private let onCancel: () -> Void

    @State private var vm: PencilAnnotationViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        baseImage: UIImage,
        onSave: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.baseImage = baseImage
        self.onSave = onSave
        self.onCancel = onCancel
        self._vm = State(wrappedValue: PencilAnnotationViewModel(backgroundImage: baseImage))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Background image
            AnnotationBackgroundView(image: baseImage)
                .ignoresSafeArea()

            // Pencil canvas
            PencilAnnotationCanvasView(
                image: baseImage,
                drawing: Binding(
                    get: { vm.currentDrawing },
                    set: { vm.currentDrawing = $0 }
                ),
                tool: vm.resolvedPKTool,
                viewModel: vm
            )
            .ignoresSafeArea()
            .accessibilityLabel(canvasA11yLabel)
            .accessibilityAddTraits(.allowsDirectInteraction)

            // Tool picker — conditionally visible
            if vm.isToolPickerVisible {
                toolPickerOverlay
                    .transition(
                        reduceMotion
                            ? .identity
                            : .move(edge: Platform.isCompact ? .bottom : .trailing)
                                .combined(with: .opacity)
                    )
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.snappy),
            value: vm.isToolPickerVisible
        )
        .navigationTitle("Annotate Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { navToolbar }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var toolPickerOverlay: some View {
        if Platform.isCompact {
            VStack {
                Spacer()
                PencilToolPickerToolbar(vm: vm)
            }
        } else {
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    PencilToolPickerToolbar(vm: vm)
                    Spacer()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var navToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                onCancel()
            }
            .accessibilityIdentifier("annotation.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task {
                    if let flattened = await vm.exportFlattened() {
                        BrandHaptics.success()
                        onSave(flattened)
                    }
                }
            }
            .accessibilityIdentifier("annotation.save")
            .accessibilityLabel("Save annotated photo")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                vm.clear()
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Clear all strokes")
        }
    }

    // MARK: - A11y

    private var canvasA11yLabel: String {
        let count = vm.strokeCount
        if count == 0 {
            return "Annotation canvas, empty"
        }
        return "Annotation canvas, \(count) \(count == 1 ? "stroke" : "strokes")"
    }
}

#endif
