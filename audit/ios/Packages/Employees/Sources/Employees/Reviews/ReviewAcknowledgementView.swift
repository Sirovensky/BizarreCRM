import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
#if canImport(PencilKit)
import PencilKit
#endif

// MARK: - ReviewAcknowledgementViewModel

@MainActor
@Observable
public final class ReviewAcknowledgementViewModel {
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repo: any ReviewsRepository
    @ObservationIgnored private let review: PerformanceReview
    @ObservationIgnored private let onAcknowledged: @MainActor (PerformanceReview) -> Void

    public init(
        repo: any ReviewsRepository,
        review: PerformanceReview,
        onAcknowledged: @escaping @MainActor (PerformanceReview) -> Void
    ) {
        self.repo = repo
        self.review = review
        self.onAcknowledged = onAcknowledged
    }

    public func acknowledge(signatureBase64: String) async {
        guard !signatureBase64.isEmpty else {
            errorMessage = "Please sign to acknowledge the review."
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let updated = try await repo.updateReview(
                id: review.id,
                UpdateReviewRequest(acknowledgement: signatureBase64, status: .acknowledged)
            )
            onAcknowledged(updated)
        } catch {
            AppLog.ui.error("ReviewAcknowledgement save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ReviewAcknowledgementView

public struct ReviewAcknowledgementView: View {
    @State private var vm: ReviewAcknowledgementViewModel
    @State private var signatureBase64: String = ""
    @Environment(\.dismiss) private var dismiss

    public init(
        repo: any ReviewsRepository,
        review: PerformanceReview,
        onAcknowledged: @escaping @MainActor (PerformanceReview) -> Void
    ) {
        _vm = State(wrappedValue: ReviewAcknowledgementViewModel(
            repo: repo, review: review, onAcknowledged: onAcknowledged))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xxl) {
                Text("I have read this performance review and acknowledge its contents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Spacing.xxl)

                signatureCanvas

                if let err = vm.errorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote)
                }

                Spacer()
            }
            .padding(.top, DesignTokens.Spacing.xxl)
            .navigationTitle("Acknowledge Review")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("Sign & Submit") {
                            Task { await vm.acknowledge(signatureBase64: signatureBase64) }
                        }
                        .disabled(signatureBase64.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var signatureCanvas: some View {
#if canImport(UIKit) && canImport(PencilKit)
        SignatureCanvasView(signatureBase64: $signatureBase64)
            .frame(height: 180)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(.separator, lineWidth: 1)
            )
            .padding(.horizontal, DesignTokens.Spacing.xxl)
#else
        TextField("Type your name to sign", text: $signatureBase64)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, DesignTokens.Spacing.xxl)
#endif
    }
}

// MARK: - SignatureCanvasView (PencilKit, UIKit platforms only)

#if canImport(UIKit) && canImport(PencilKit)
import UIKit
struct SignatureCanvasView: UIViewRepresentable {
    @Binding var signatureBase64: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate, @unchecked Sendable {
        private let parent: SignatureCanvasView

        init(_ parent: SignatureCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let image = canvasView.drawing.image(from: canvasView.bounds, scale: UIScreen.main.scale)
            if let data = image.pngData() {
                let b64 = data.base64EncodedString()
                Task { @MainActor in
                    self.parent.signatureBase64 = b64
                }
            }
        }
    }
}
#endif
