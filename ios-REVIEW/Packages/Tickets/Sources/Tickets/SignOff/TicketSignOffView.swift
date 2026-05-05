#if canImport(UIKit)
import SwiftUI
import PencilKit
import Core
import DesignSystem

/// §4 — Customer sign-off view.
/// Customer signs on pickup with `PKCanvasView`. Disclaimer displayed above.
@MainActor
public struct TicketSignOffView: View {
    @Environment(\.dismiss) private var dismiss
    @State var vm: TicketSignOffViewModel
    @State private var canvasView = PKCanvasView()
    @State private var showingReceipt = false
    @State private var receiptPDFURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(vm: TicketSignOffViewModel) {
        self._vm = State(wrappedValue: vm)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        disclaimerCard
                        signatureSection
                        if case .failed(let msg) = vm.state {
                            errorBanner(msg)
                        }
                        actionButtons
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Customer Sign-Off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { vm.requestLocationIfAllowed() }
        .onChange(of: vm.state) { _, new in
            if case .success(_, let url) = new {
                receiptPDFURL = url
                showingReceipt = true
            }
        }
        .sheet(isPresented: $showingReceipt) {
            if case .success(let receiptId, let url) = vm.state {
                ReceiptConfirmationView(receiptId: receiptId, pdfURL: url) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Disclaimer

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Repair Acceptance", systemImage: "checkmark.shield")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Text(TicketSignOffViewModel.disclaimerText)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Repair acceptance: \(TicketSignOffViewModel.disclaimerText)")
    }

    // MARK: - Signature canvas

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Customer Signature")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Button("Clear") {
                    canvasView.drawing = PKDrawing()
                    vm.clearSignature()
                }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Clear signature")
            }

            SignatureCanvasView(canvasView: $canvasView) { drawing in
                let image = drawing.image(from: drawing.bounds.isEmpty
                    ? CGRect(x: 0, y: 0, width: 300, height: 150)
                    : drawing.bounds, scale: 2)
                vm.signatureData = image.pngData()
            }
            .frame(height: 180)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreOutline, lineWidth: 1)
            )
            .overlay(
                // Placeholder hint
                vm.signatureData == nil
                    ? Text("Sign here")
                        .font(.brandBodyMedium())
                        .foregroundStyle(Color.gray.opacity(0.4))
                    : nil
            )
            .accessibilityLabel("Customer signed")
            .accessibilityHint("Customer draws their signature here")
            .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }

    // MARK: - Error

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(msg)")
    }

    // MARK: - Actions

    private var actionButtons: some View {
        Button {
            Task { await vm.submit() }
        } label: {
            Group {
                if case .submitting = vm.state {
                    ProgressView()
                } else {
                    Label("Confirm Pickup", systemImage: "signature")
                        .font(.brandBodyLarge())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(vm.signatureData == nil || { if case .submitting = vm.state { return true }; return false }())
        .accessibilityLabel("Confirm pickup with signature")
    }
}

// MARK: - PencilKit canvas wrapper

private struct SignatureCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let onDrawingChanged: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDrawingChanged: onDrawingChanged) }

    final class Coordinator: NSObject, PKCanvasViewDelegate, @unchecked Sendable {
        let onDrawingChanged: (PKDrawing) -> Void
        init(onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}

// MARK: - Receipt confirmation

private struct ReceiptConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let receiptId: String
    let pdfURL: URL?
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityHidden(true)
                    Text("Signed Off")
                        .font(.brandTitleLarge()).bold()
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Receipt ID: \(receiptId)")
                        .font(.brandMono(size: 14))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                    if let url = pdfURL {
                        Link(destination: url) {
                            Label("Download Receipt PDF", systemImage: "arrow.down.circle")
                                .font(.brandBodyLarge())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreTeal)
                        .accessibilityLabel("Download signed receipt PDF")
                    }
                    Button("Done") { onDone() }
                        .buttonStyle(.bordered)
                        .tint(.bizarreOrange)
                }
                .padding(BrandSpacing.lg)
            }
            .navigationTitle("Sign-Off Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
