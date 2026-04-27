#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - §36.3 Setup resume banner (Dashboard nudge)

/// A non-blocking glass banner shown on the Dashboard when the Setup Wizard
/// was deferred or is only partially complete.
///
/// **Integration (Dashboard view):**
/// ```swift
/// SetupResumeBanner(currentStep: 5, totalSteps: 15) {
///     showSetupWizard = true
/// }
/// ```
///
/// The banner auto-hides once setup is complete (`currentStep >= totalSteps`).
/// It persists across sessions because the server is the source of truth for
/// `currentStep`; the Dashboard loads it via `GET /setup/status` on appear.
public struct SetupResumeBanner: View {

    public let currentStep: Int
    public let totalSteps: Int
    public let onResume: () -> Void
    public let onDismiss: (() -> Void)?

    @State private var dismissed: Bool = false

    public init(
        currentStep: Int,
        totalSteps: Int,
        onResume: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.onResume = onResume
        self.onDismiss = onDismiss
    }

    /// Banner is visible when setup is incomplete AND has not been locally dismissed.
    private var isVisible: Bool {
        !dismissed && currentStep < totalSteps
    }

    public var body: some View {
        if isVisible {
            banner
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(BrandMotion.snappy, value: dismissed)
                .accessibilityIdentifier("setup.resumeBanner")
        }
    }

    private var banner: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Setup \(currentStep - 1) of \(totalSteps - 1) complete")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)

                // Minimal progress bar.
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.bizarreOutline.opacity(0.4))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.bizarreOrange)
                                .frame(width: geo.size.width * progressFraction)
                        }
                }
                .frame(height: 4)
            }

            Spacer()

            Button("Continue", action: onResume)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityIdentifier("setup.resumeBanner.continue")

            if onDismiss != nil {
                Button {
                    withAnimation(BrandMotion.snappy) { dismissed = true }
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss setup reminder")
                .accessibilityIdentifier("setup.resumeBanner.dismiss")
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular,
                    in: RoundedRectangle(cornerRadius: 14),
                    tint: Color.bizarreOrange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOrange.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup \(currentStep - 1) of \(totalSteps - 1) complete. Tap Continue to finish.")
    }

    private var progressFraction: Double {
        guard totalSteps > 1 else { return 1 }
        return Double(currentStep - 1) / Double(totalSteps - 1)
    }
}

#endif
