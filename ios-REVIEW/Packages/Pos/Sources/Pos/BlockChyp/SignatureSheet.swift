#if canImport(UIKit)
import SwiftUI
import PencilKit
import Core
import DesignSystem

/// §16.26 — On-phone signature capture sheet.
///
/// Presented as `.fullScreenCover` when `SignatureRouter` routes to `.onPhone`.
/// Customer signs on the iPhone/iPad screen. On "Accept": drawing → PNG → base64
/// → delivered to `onAccept` closure. On "Clear": canvas resets. "Cancel" is
/// available only if `allowCancel` is true (manager-PIN-guarded in real flow).
///
/// **BlockChyp math is NOT here.** This view only captures the ink and converts
/// to PNG. The resulting `sigBase64` is passed up to `PosTenderViewModel`.
///
/// Liquid Glass: `.brandGlass` on the top toolbar only (chrome rule). Canvas
/// area is plain `surface`. GlassBudget = 1.
@MainActor
public struct SignatureSheet: View {

    // MARK: - Init

    public let customerName: String?
    public let invoiceId: Int64
    public let allowCancel: Bool
    public let onAccept: @MainActor (String) -> Void   // delivers base64 PNG
    public let onCancel: @MainActor () -> Void

    public init(
        customerName: String? = nil,
        invoiceId: Int64,
        allowCancel: Bool = true,
        onAccept: @escaping @MainActor (String) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.customerName = customerName
        self.invoiceId    = invoiceId
        self.allowCancel  = allowCancel
        self.onAccept     = onAccept
        self.onCancel     = onCancel
    }

    // MARK: - State

    @State private var canvasView = PKCanvasView()
    @State private var hasStrokes = false
    @State private var isExporting = false

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instruction
                instructionBanner
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.top, BrandSpacing.md)

                // Canvas
                signatureCanvas
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.top, BrandSpacing.sm)

                // Timestamp + name
                signerInfo
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.top, BrandSpacing.xs)

                // Clear button
                clearButton
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.top, BrandSpacing.sm)

                Spacer()
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .accessibilityLabel("Customer signature pad")
    }

    // MARK: - Sub-views

    private var instructionBanner: some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text("Customer Signature")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Sign to authorize payment for Invoice #\(invoiceId)")
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var signatureCanvas: some View {
        PKCanvasViewWrapper(
            canvasView: $canvasView,
            hasStrokes: $hasStrokes
        )
        .frame(height: 160)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    hasStrokes ? Color.bizarreOrange : Color.bizarreOutline,
                    lineWidth: hasStrokes ? 2 : 1
                )
        )
        .accessibilityLabel("Signature area — sign with finger or Apple Pencil")
        .accessibilityHint("After signing, tap Accept to confirm")
    }

    private var signerInfo: some View {
        HStack {
            if let name = customerName {
                Text(name)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text(Date().formatted(date: .abbreviated, time: .shortened))
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
    }

    private var clearButton: some View {
        Button {
            canvasView.drawing = PKDrawing()
            hasStrokes = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label("Clear signature", systemImage: "trash")
                .font(.brandLabelMedium())
                .foregroundStyle(.bizarreOrange)
        }
        .disabled(!hasStrokes)
        .accessibilityIdentifier("signatureSheet.clear")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Cancel (optional)
        if allowCancel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("signatureSheet.cancel")
            }
        }

        // Accept
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task { await acceptSignature() }
            } label: {
                if isExporting {
                    ProgressView().tint(.black)
                } else {
                    Text("Accept")
                        .fontWeight(.semibold)
                        .foregroundStyle(hasStrokes ? .black : .bizarreOnSurfaceMuted)
                }
            }
            .disabled(!hasStrokes || isExporting)
            .accessibilityIdentifier("signatureSheet.accept")
        }
    }

    // MARK: - Accept

    private func acceptSignature() async {
        guard hasStrokes else { return }
        isExporting = true
        defer { isExporting = false }

        // Convert PKDrawing to PNG data then to base64.
        let image = canvasView.drawing.image(
            from: canvasView.bounds,
            scale: UIScreen.main.scale
        )
        guard let pngData = image.pngData() else {
            AppLog.pos.error("SignatureSheet: failed to export PNG from PKDrawing")
            return
        }

        // Budget check: compressed PNG must be ≤ 500 KB (matches server limit).
        let budget = 500 * 1024
        let finalData: Data
        if pngData.count > budget {
            // Re-render at half scale and try again (max 3 attempts shared with CheckIn).
            let halfImage = canvasView.drawing.image(
                from: canvasView.bounds,
                scale: UIScreen.main.scale * 0.5
            )
            finalData = halfImage.pngData() ?? pngData
            AppLog.pos.warning("SignatureSheet: original PNG \(pngData.count) bytes, downscaled to \(finalData.count) bytes")
        } else {
            finalData = pngData
        }

        let base64 = finalData.base64EncodedString()

        // Haptic confirmation.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AppLog.pos.info("SignatureSheet: accepted, \(finalData.count) bytes PNG, base64 len=\(base64.count, privacy: .public)")

        onAccept(base64)
    }
}

// MARK: - PKCanvasViewWrapper

/// UIViewRepresentable wrapping `PKCanvasView`.
/// Reports `hasStrokes` via a binding so the Accept button enables reactively.
@MainActor
private struct PKCanvasViewWrapper: UIViewRepresentable {

    @Binding var canvasView: PKCanvasView
    @Binding var hasStrokes: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(hasStrokes: $hasStrokes)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy  = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.delegate        = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate, @unchecked Sendable {
        @Binding var hasStrokes: Bool
        init(hasStrokes: Binding<Bool>) { _hasStrokes = hasStrokes }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            DispatchQueue.main.async { [weak self] in
                self?.hasStrokes = !canvasView.drawing.strokes.isEmpty
            }
        }
    }
}
#endif
