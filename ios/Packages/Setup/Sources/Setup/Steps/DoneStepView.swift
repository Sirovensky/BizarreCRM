import SwiftUI
import Core
import DesignSystem

// MARK: - DoneStepView  (§36.2 Step 13 — Done)

@MainActor
public struct DoneStepView: View {
    let completedSteps: Set<Int>
    let onOpenDashboard: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSparkles: Bool = false

    public init(completedSteps: Set<Int>, onOpenDashboard: @escaping () -> Void) {
        self.completedSteps = completedSteps
        self.onOpenDashboard = onOpenDashboard
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                Spacer(minLength: BrandSpacing.xxl)

                celebrationIcon

                headlineSection

                completionChecklist

                dashboardCTA

                Spacer(minLength: BrandSpacing.xxl)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            if !reduceMotion {
                withAnimation(.spring(duration: 0.6, bounce: 0.4).delay(0.2)) {
                    showSparkles = true
                }
            }
        }
    }

    // MARK: Sub-views

    private var celebrationIcon: some View {
        ZStack {
            if !reduceMotion && showSparkles {
                sparklesBackground
            }

            Image(systemName: "party.popper.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.bizarreOrange)
                .scaleEffect(showSparkles || reduceMotion ? 1.0 : 0.5)
                .animation(
                    reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.4).delay(0.15),
                    value: showSparkles
                )
                .accessibilityHidden(true)
        }
        .frame(height: 120)
    }

    @ViewBuilder
    private var sparklesBackground: some View {
        ForEach(sparkleOffsets.indices, id: \.self) { idx in
            let offset = sparkleOffsets[idx]
            Image(systemName: "sparkle")
                .font(.system(size: CGFloat.random(in: 12...24)))
                .foregroundStyle(sparkleColors[idx % sparkleColors.count])
                .offset(x: offset.x, y: offset.y)
                .opacity(showSparkles ? 1 : 0)
                .scaleEffect(showSparkles ? 1 : 0)
                .animation(
                    .spring(duration: 0.5, bounce: 0.3).delay(Double(idx) * 0.05 + 0.2),
                    value: showSparkles
                )
                .accessibilityHidden(true)
        }
    }

    private var sparkleOffsets: [(x: CGFloat, y: CGFloat)] {
        [(-60, -50), (60, -50), (-80, -10), (80, -10),
         (-40, 30), (40, 30), (0, -70), (-20, 60), (20, 60)]
    }

    private var sparkleColors: [Color] {
        [.bizarreOrange, .bizarreTeal, .bizarreMagenta, .yellow, .mint]
    }

    private var headlineSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Welcome aboard!")
                .font(.brandDisplayLarge())
                .foregroundStyle(Color.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Your shop is ready to take its first repair. Everything you set up is saved and ready to go.")
                .font(.brandBodyLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var completionChecklist: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("What you completed")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            ForEach(checklistItems, id: \.rawValue) { step in
                checklistRow(step)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(
            Color.bizarreSurface1.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var checklistItems: [SetupStep] {
        SetupStep.allCases.filter { step in
            step != .complete && completedSteps.contains(step.rawValue)
        }
    }

    private func checklistRow(_ step: SetupStep) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.bizarreSuccess)
                .accessibilityHidden(true)

            Text(step.title)
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurface)

            Spacer()
        }
        .accessibilityLabel("\(step.title) — completed")
    }

    private var dashboardCTA: some View {
        Button {
            onOpenDashboard()
        } label: {
            Label("Open Dashboard", systemImage: "house.fill")
                .font(.brandTitleSmall())
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .accessibilityLabel("Open Dashboard")
        .accessibilityHint("Dismisses the setup wizard and takes you to the main dashboard")
        .keyboardShortcut(.return, modifiers: .command)
    }
}
