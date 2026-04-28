#if canImport(UIKit)
import SwiftUI
import PencilKit
import Core
import DesignSystem
import Networking

// MARK: - §8.2 Estimate Approve Action
//
// Staff-assisted approval flow:
//   1. Optionally capture customer signature via PKCanvasView.
//   2. POST /api/v1/estimates/:id/approve  { signature_png_base64? }
//   3. On success: dismiss + callback with approved estimate id.
//
// Server route confirmed:
//   packages/server/src/routes/estimates.routes.ts:
//   POST /api/v1/estimates/:id/approve

// MARK: - ApproveEstimateRequest

struct ApproveEstimateRequest: Encodable, Sendable {
    let signaturePngBase64: String?
    enum CodingKeys: String, CodingKey {
        case signaturePngBase64 = "signature_png_base64"
    }
}

// MARK: - EstimateApproveSheetViewModel

@MainActor
@Observable
final class EstimateApproveSheetViewModel {
    var isSubmitting: Bool = false
    var errorMessage: String?
    var didApprove: Bool = false

    private let api: APIClient
    let estimateId: Int64
    let orderId: String

    init(api: APIClient, estimateId: Int64, orderId: String) {
        self.api = api
        self.estimateId = estimateId
        self.orderId = orderId
    }

    func approve(signatureImage: UIImage?) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let base64: String?
        if let img = signatureImage, let pngData = img.pngData() {
            base64 = pngData.base64EncodedString()
        } else {
            base64 = nil
        }

        let body = ApproveEstimateRequest(signaturePngBase64: base64)
        do {
            _ = try await api.post(
                "/api/v1/estimates/\(estimateId)/approve",
                body: body,
                as: Estimate.self
            )
            didApprove = true
            AppLog.ui.info("Estimate \(estimateId) approved by staff.")
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
            AppLog.ui.error("Estimate approve failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - EstimateApproveSheet

/// §8.2 Staff-assisted approve sheet with optional PencilKit signature capture.
public struct EstimateApproveSheet: View {
    private let estimate: Estimate
    private let api: APIClient
    private let onApproved: @MainActor () -> Void

    @State private var vm: EstimateApproveSheetViewModel
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var hasSignature: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(
        estimate: Estimate,
        api: APIClient,
        onApproved: @escaping @MainActor () -> Void = {}
    ) {
        self.estimate = estimate
        self.api = api
        self.onApproved = onApproved
        _vm = State(wrappedValue: EstimateApproveSheetViewModel(
            api: api,
            estimateId: estimate.id,
            orderId: estimate.orderId ?? "EST-?"
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    // Summary card
                    summaryCard

                    // Signature area
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        HStack {
                            Text("Customer Signature")
                                .font(.brandTitleSmall())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            if hasSignature {
                                Button("Clear") {
                                    canvasView.drawing = PKDrawing()
                                    hasSignature = false
                                }
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOrange)
                            }
                        }

                        Text("Optional — customer may sign on screen to confirm approval.")
                            .font(.brandLabelMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)

                        SignatureCanvasView(
                            canvasView: $canvasView,
                            toolPicker: toolPicker,
                            onStrokeAdded: { hasSignature = true }
                        )
                        .frame(height: 160)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 1)
                        )
                        .accessibilityLabel("Signature canvas. Draw customer signature here.")
                    }

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.brandLabelMedium())
                            .foregroundStyle(.bizarreError)
                            .padding(BrandSpacing.sm)
                            .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }

                    Spacer()
                }
                .padding(BrandSpacing.lg)
            }
            .navigationTitle("Approve Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(vm.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let sig = hasSignature ? canvasView.drawing.image(
                                from: canvasView.bounds,
                                scale: UIScreen.main.scale
                            ) : nil
                            await vm.approve(signatureImage: sig)
                        }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Approve")
                                .fontWeight(.semibold)
                                .foregroundStyle(.bizarreOrange)
                        }
                    }
                    .disabled(vm.isSubmitting)
                    .accessibilityLabel(vm.isSubmitting ? "Approving estimate…" : "Approve estimate")
                }
            }
            .onChange(of: vm.didApprove) { _, approved in
                if approved {
                    onApproved()
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(estimate.orderId ?? "EST-?")
                        .font(.brandMono(size: 16))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                    Text(estimate.customerName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Text(formatMoney(estimate.total ?? 0))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .accessibilityLabel("Total: \(formatMoney(estimate.total ?? 0))")
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - SignatureCanvasView (UIViewRepresentable)

struct SignatureCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let toolPicker: PKToolPicker
    let onStrokeAdded: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = context.coordinator
        toolPicker.setVisible(false, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onStrokeAdded: onStrokeAdded) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onStrokeAdded: () -> Void
        init(onStrokeAdded: @escaping () -> Void) { self.onStrokeAdded = onStrokeAdded }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if !canvasView.drawing.strokes.isEmpty {
                onStrokeAdded()
            }
        }
    }
}

#endif
