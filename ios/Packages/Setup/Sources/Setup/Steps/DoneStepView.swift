import SwiftUI
import Core
import DesignSystem

// MARK: - OnboardingConfettiView
// §36.2 Step 13 — multi-particle full-screen confetti burst.
// Respects Reduce Motion: when enabled the view renders nothing so callers
// can omit it entirely (the static party-popper icon remains).

private struct OnboardingConfettiParticle: Identifiable {
    let id = UUID()
    // Particles start at a central point and scatter outward.
    let startX: CGFloat = 0.5
    let startY: CGFloat = 0.35
    let endX:   CGFloat = CGFloat.random(in: 0.05...0.95)
    let endY:   CGFloat = CGFloat.random(in: 0.15...1.05)
    let size:   CGFloat = CGFloat.random(in: 5...13)
    let delay:  Double  = Double.random(in: 0...0.35)
    let rotation: Double = Double.random(in: 0...360)
    let isRect: Bool    = Bool.random()
    let color: Color    = [
        Color.bizarreOrange, Color.bizarreTeal, Color.bizarreMagenta,
        .yellow, .mint, .indigo, .pink
    ].randomElement()!
}

private struct OnboardingConfettiView: View {
    @State private var particles: [OnboardingConfettiParticle] =
        (0..<55).map { _ in OnboardingConfettiParticle() }
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                Group {
                    if p.isRect {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(p.color)
                            .frame(width: p.size, height: p.size * 0.55)
                            .rotationEffect(.degrees(animate ? p.rotation + 180 : p.rotation))
                    } else {
                        Circle()
                            .fill(p.color)
                            .frame(width: p.size, height: p.size)
                    }
                }
                .position(
                    x: animate ? p.endX * geo.size.width  : p.startX * geo.size.width,
                    y: animate ? p.endY * geo.size.height : p.startY * geo.size.height
                )
                .opacity(animate ? 0 : 1)
                .animation(
                    .easeOut(duration: 0.8).delay(p.delay),
                    value: animate
                )
            }
        }
        .onAppear { animate = true }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

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
        ZStack {
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

            // §36.2 Confetti burst — Reduce Motion: omit entirely per §26.3
            if !reduceMotion && showSparkles {
                OnboardingConfettiView()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
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
        Image(systemName: "party.popper.fill")
            .font(.system(size: 72))
            .foregroundStyle(Color.bizarreOrange)
            .scaleEffect(showSparkles || reduceMotion ? 1.0 : 0.5)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.4).delay(0.15),
                value: showSparkles
            )
            .accessibilityHidden(true)
            .frame(height: 120)
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
