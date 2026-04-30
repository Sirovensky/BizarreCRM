/// CheckInSignView.swift — §16.25.6
///
/// Step 6: Sign — terms card, acknowledgment checklist, signature pad, submit.
/// Progress bar fills green (100%) to signal wizard completion.
///
/// PKCanvasView wrapped as `CheckInSignaturePad`. Signature exported as
/// PNG → base64 with 500 KB budget enforcement before attaching to draft.
///
/// On "Create ticket · print label":
///   1. Upload signature → POST /api/v1/tickets/:id/signatures
///   2. Write deposit tender (via draft.depositCents)
///   3. Navigate to drop-off receipt (onComplete on CheckInFlowViewModel)
///
/// Spec: mockup frame "CI-6 · Sign · terms · signature · create ticket".

#if canImport(UIKit)
import SwiftUI
import PencilKit
import DesignSystem

// MARK: - CheckInSignaturePad

/// PKCanvasView wrapper — cream-bordered, 110pt height, clear button.
struct CheckInSignaturePad: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = UIColor(Color.bizarreSurface1)
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: UIColor(Color.bizarreOnSurface), width: 2)
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: CheckInSignaturePad
        init(_ parent: CheckInSignaturePad) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

// MARK: - CheckInSignView

struct CheckInSignView: View {
    @Bindable var draft: CheckInDraft
    @State private var drawing: PKDrawing = PKDrawing()
    @State private var isTermsExpanded: Bool = false
    @State private var sizeError: Bool = false
    private let maxSignatureBytesBase64 = 500 * 1024  // 500 KB

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // Terms card
                termsCard

                Divider().padding(.horizontal, BrandSpacing.base)

                // Acknowledgment checklist
                acknowledgmentSection

                Divider().padding(.horizontal, BrandSpacing.base)

                // Signature pad
                signaturePadSection

                // Budget error
                if sizeError {
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.bizarreError)
                        Text("Signature too large — please redraw with fewer strokes")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.bizarreError)
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // Bottom padding for nav bar
                Spacer().frame(height: 100)
            }
            .padding(.vertical, BrandSpacing.md)
        }
        .animation(.easeOut(duration: 0.15), value: isTermsExpanded)
        .animation(.easeOut(duration: 0.15), value: sizeError)
        .onChange(of: drawing) { _, newDrawing in
            attachSignatureIfNonEmpty(newDrawing)
        }
    }

    // MARK: - Terms card

    private var termsCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Label("Terms & Conditions", systemImage: "doc.text.fill")
                    .font(.brandTitleMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isTermsExpanded.toggle()
                    }
                } label: {
                    Text(isTermsExpanded ? "Collapse" : "Expand")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.bizarreOrange)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BrandSpacing.base)

            // Collapsed: key-terms bullet list
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                termsBullet(icon: "shield.fill",         color: .bizarreTeal,    text: "Your data is encrypted and kept private")
                termsBullet(icon: "wrench.and.screwdriver", color: .bizarreOrange, text: "Repair scope limited to agreed work order")
                termsBullet(icon: "clock.fill",          color: .bizarreWarning, text: "Turnaround estimates not guaranteed")
                termsBullet(icon: "creditcard.fill",     color: .bizarreSuccess, text: "Payment due before device release")

                if isTermsExpanded {
                    Divider().padding(.vertical, BrandSpacing.xs)
                    Text("Full terms: by signing below you agree to our repair terms including our diagnostic fee policy, parts warranty (90 days), and data liability waiver. We are not responsible for pre-existing damage or data loss. Repairs not collected within 90 days may be recycled per applicable law.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Read full terms (PDF)", destination: URL(string: "https://bizarrecrm.com/legal/repair-terms.pdf")!)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.bizarreOrange)
                }
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    private func termsBullet(icon: String, color: Color, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.bizarreOnSurface)
            .labelStyle(BulletLabelStyle(iconColor: color))
    }

    // MARK: - Acknowledgment checklist

    private var acknowledgmentSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Acknowledgment")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)

            VStack(spacing: 0) {
                checkRow(
                    isOn: $draft.agreedToTerms,
                    required: true,
                    label: "I have read and agree to the repair terms above"
                )
                Divider().padding(.leading, BrandSpacing.xl + BrandSpacing.md)
                checkRow(
                    isOn: $draft.consentToBackup,
                    required: true,
                    label: "I consent to a device backup before repair"
                )
                Divider().padding(.leading, BrandSpacing.xl + BrandSpacing.md)
                checkRow(
                    isOn: $draft.authorizedDeposit,
                    required: true,
                    label: draft.depositCents > 0
                        ? "I authorize the \(CartMath.formatCents(draft.depositCents)) deposit"
                        : "I authorize repair work to proceed"
                )
                Divider().padding(.leading, BrandSpacing.xl + BrandSpacing.md)
                checkRow(
                    isOn: $draft.optInToSMSUpdates,
                    required: false,
                    label: "Send me SMS updates on repair status (optional)"
                )
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    private func checkRow(isOn: Binding<Bool>, required: Bool, label: String) -> some View {
        Button {
            BrandHaptics.tap()
            withAnimation(.easeOut(duration: 0.12)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: BrandSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn.wrappedValue ? Color.bizarreOrange : Color.bizarreSurface2)
                        .frame(width: 22, height: 22)
                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1)
                            .frame(width: 22, height: 22)
                    }
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.bizarreOnSurface)
                    .multilineTextAlignment(.leading)
                Spacer()
                if required && !isOn.wrappedValue {
                    Text("Required")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.bizarreError)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.bizarreError.opacity(0.1), in: Capsule())
                }
            }
            .padding(BrandSpacing.md)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn.wrappedValue ? "checked" : "unchecked")
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Signature pad section

    private var signaturePadSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Label("Signature", systemImage: "pencil.and.scribble")
                    .font(.brandTitleMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                Spacer()
                if !drawing.strokes.isEmpty {
                    Button {
                        BrandHaptics.tap()
                        withAnimation(.easeOut(duration: 0.15)) {
                            drawing = PKDrawing()
                            draft.signaturePNGBase64 = nil
                            sizeError = false
                        }
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.bizarreError)
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, 4)
                            .background(Color.bizarreError.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear signature")
                }
            }
            .padding(.horizontal, BrandSpacing.base)

            Text("Sign with your finger or Apple Pencil")
                .font(.system(size: 11))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.base)

            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(
                                draft.signatureAttached ? Color.bizarreSuccess : Color.bizarreOrange.opacity(0.6),
                                lineWidth: 1
                            )
                    )

                if drawing.strokes.isEmpty {
                    Text("Sign here")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .allowsHitTesting(false)
                }

                CheckInSignaturePad(drawing: $drawing)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
            .frame(height: 110)
            .padding(.horizontal, BrandSpacing.base)
            .accessibilityLabel("Signature pad — sign to authorize repair")

            if draft.signatureAttached {
                Label("Signature captured", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.bizarreSuccess)
                    .padding(.horizontal, BrandSpacing.base)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: draft.signatureAttached)
    }

    // MARK: - Signature processing

    private func attachSignatureIfNonEmpty(_ drawing: PKDrawing) {
        guard !drawing.strokes.isEmpty else {
            draft.signaturePNGBase64 = nil
            sizeError = false
            return
        }

        let bounds = drawing.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Render at 2× scale into PNG
        let scale: CGFloat = 2.0
        let padded = bounds.insetBy(dx: -8, dy: -8)
        let image = drawing.image(from: padded, scale: scale)

        guard let pngData = image.pngData() else { return }

        // 500 KB enforcement
        if pngData.count > maxSignatureBytesBase64 {
            sizeError = true
            draft.signaturePNGBase64 = nil
            return
        }

        sizeError = false
        draft.signaturePNGBase64 = pngData.base64EncodedString()
    }
}

// MARK: - BulletLabelStyle

private struct BulletLabelStyle: LabelStyle {
    let iconColor: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            configuration.icon
                .foregroundStyle(iconColor)
                .frame(width: 16)
            configuration.title
        }
    }
}

#endif
