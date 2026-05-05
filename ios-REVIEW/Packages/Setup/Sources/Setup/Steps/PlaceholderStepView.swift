import SwiftUI
import DesignSystem

// MARK: - PlaceholderStepView
// Shown for steps 4–13 that are not yet implemented in this PR.

public struct PlaceholderStepView: View {
    let step: SetupStep

    public init(step: SetupStep) {
        self.step = step
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()

            Image(systemName: "timer")
                .font(.system(size: 64))
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)

            Text(step.title)
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Text("Coming soon — continue later")
                .font(.brandBodyLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)

            Text("This step will be available in the next update. You can skip it and finish setting up your shop later from Settings.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xxl)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title) — coming soon. You can skip and continue later.")
    }
}
