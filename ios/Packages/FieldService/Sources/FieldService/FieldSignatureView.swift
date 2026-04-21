// §57.2 FieldSignatureView — PencilKit canvas for customer signature.
// Saves as PNG Data. A11y: canvas has accessibilityLabel "Customer signature pad".
// After signing, announces "Customer signed" for VoiceOver.
//
// PencilKit is UIKit-only. macOS SPM build gets a stub view.

import SwiftUI
import DesignSystem

#if canImport(UIKit)
import PencilKit
import UIKit

// MARK: - FieldSignatureView

/// Customer signature canvas backed by PKCanvasView.
///
/// Usage:
/// ```swift
/// FieldSignatureView { pngData in
///     try await checkInService.checkOut(appointmentId: id, signature: pngData)
/// }
/// ```
///
/// A11y: canvas labelled "Customer signature pad". Post-sign
/// VoiceOver announcement: "Customer signed".
public struct FieldSignatureView: View {

    public let onSave: (Data) async -> Void
    public let onCancel: () -> Void

    @State private var canvasView = PKCanvasView()
    @State private var isSaving = false
    @State private var hasSignature = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        onSave: @escaping (Data) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                signatureCanvas
                Divider()
                actionBar
            }
            .navigationTitle("Customer Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { clearCanvas() }
                        .foregroundStyle(.secondary)
                        .disabled(!hasSignature)
                }
            }
        }
    }

    // MARK: - Canvas

    private var signatureCanvas: some View {
        SignatureCanvasRepresentable(
            canvasView: $canvasView,
            hasSignature: $hasSignature
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .overlay(
            Text("Sign here")
                .font(.brandBodyMedium())
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
                .opacity(hasSignature ? 0 : 1)
        )
        .accessibilityLabel("Customer signature pad")
        .accessibilityHint("Draw your signature with your finger or Apple Pencil")
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack {
            Spacer()
            Button {
                Task { await saveSignature() }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Label("Save Signature", systemImage: "signature")
                }
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(!hasSignature || isSaving)
            .padding()
        }
    }

    // MARK: - Actions

    private func clearCanvas() {
        canvasView.drawing = PKDrawing()
        hasSignature = false
    }

    private func saveSignature() async {
        guard hasSignature else { return }
        isSaving = true
        defer { isSaving = false }

        let image = canvasView.drawing.image(
            from: canvasView.bounds,
            scale: UIScreen.main.scale
        )
        guard let pngData = image.pngData() else { return }

        await onSave(pngData)

        // A11y announcement after save.
        UIAccessibility.post(
            notification: .announcement,
            argument: "Customer signed"
        )
    }
}

// MARK: - SignatureCanvasRepresentable

private struct SignatureCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var hasSignature: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 2)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator
        canvasView.isAccessibilityElement = false
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(hasSignature: $hasSignature)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, @unchecked Sendable {
        @Binding var hasSignature: Bool

        init(hasSignature: Binding<Bool>) {
            _hasSignature = hasSignature
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            hasSignature = !canvasView.drawing.strokes.isEmpty
        }
    }
}

#else

// MARK: - macOS stub

public struct FieldSignatureView: View {
    public init(onSave: @escaping (Data) async -> Void, onCancel: @escaping () -> Void) {}
    public var body: some View { EmptyView() }
}

#endif
