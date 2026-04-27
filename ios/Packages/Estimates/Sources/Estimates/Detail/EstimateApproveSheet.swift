#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import PencilKit

// MARK: - EstimateApproveSheet (§8.2)
//
// Staff-assisted approval: captures a customer's on-screen signature
// via PKCanvasView then calls `POST /api/v1/estimates/:id/approve`.
//
// Signature is sent as a base64-encoded PNG of the canvas.

@MainActor
@Observable
public final class EstimateApproveViewModel {
    public private(set) var isApproving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didApprove: Bool = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let estimateId: Int64

    public init(api: APIClient, estimateId: Int64) {
        self.api = api
        self.estimateId = estimateId
    }

    public func approve(signatureData: Data?) async {
        isApproving = true
        errorMessage = nil
        defer { isApproving = false }
        do {
            let b64 = signatureData.map { $0.base64EncodedString() }
            _ = try await api.approveEstimate(estimateId: estimateId, signatureData: b64)
            didApprove = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - EstimateApproveSheet

public struct EstimateApproveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EstimateApproveViewModel
    @State private var canvas = PKCanvasView()
    @State private var canvasTool: PKInkingTool = PKInkingTool(.pen, color: .black, width: 3)
    @State private var signatureIsEmpty: Bool = true
    private let orderId: String

    public init(estimateId: Int64, orderId: String, api: APIClient) {
        self.orderId = orderId
        _vm = State(wrappedValue: EstimateApproveViewModel(api: api, estimateId: estimateId))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instructions
                VStack(spacing: BrandSpacing.sm) {
                    Text("Customer signature required")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Have the customer sign below to approve estimate \(orderId).")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(BrandSpacing.lg)

                Divider()

                // Signature canvas
                SignatureCanvasView(canvas: $canvas, isEmpty: $signatureIsEmpty)
                    .frame(height: 220)
                    .background(Color.bizarreSurface1)
                    .cornerRadius(DesignTokens.Radius.md)
                    .padding(BrandSpacing.lg)
                    .accessibilityLabel("Signature area — have the customer sign here")

                // Clear button
                Button("Clear signature") {
                    canvas.drawing = PKDrawing()
                    signatureIsEmpty = true
                }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.bottom, BrandSpacing.md)
                .accessibilityLabel("Clear the signature and start over")

                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.bizarreError)
                        .font(.brandBodyMedium())
                        .padding(.horizontal, BrandSpacing.lg)
                        .accessibilityLabel("Error: \(err)")
                }

                if vm.didApprove {
                    Label("Approved successfully", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreSuccess)
                        .font(.brandBodyLarge())
                        .padding(BrandSpacing.lg)
                        .accessibilityLabel("Estimate approved successfully")
                }

                Spacer()
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Approve Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel approval")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.didApprove {
                        Button("Done") { dismiss() }
                            .accessibilityLabel("Dismiss approval sheet")
                    } else {
                        Button("Approve") {
                            Task {
                                let img = canvas.drawing.image(from: canvas.drawing.bounds, scale: 2)
                                let data = img.pngData()
                                await vm.approve(signatureData: data)
                            }
                        }
                        .disabled(signatureIsEmpty || vm.isApproving)
                        .accessibilityLabel("Approve estimate with captured signature")
                    }
                }
            }
            .overlay {
                if vm.isApproving {
                    ProgressView("Approving…")
                        .padding(BrandSpacing.xl)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                }
            }
        }
    }
}

// MARK: - SignatureCanvasView (UIViewRepresentable)

private struct SignatureCanvasView: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    @Binding var isEmpty: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(isEmpty: $isEmpty) }

    final class Coordinator: NSObject, PKCanvasViewDelegate, @unchecked Sendable {
        private let isEmpty: Binding<Bool>
        init(isEmpty: Binding<Bool>) { self.isEmpty = isEmpty }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            Task { @MainActor in
                isEmpty.wrappedValue = canvasView.drawing.bounds.isEmpty
            }
        }
    }
}
#endif
