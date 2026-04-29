import SwiftUI

// §67.4 — Signature Animations
// Named view modifiers for the five spec animations.
// All modifiers gate on Reduce Motion automatically.

// MARK: - TicketCreatedPulse

private struct TicketCreatedPulseModifier: ViewModifier {
    let highlight: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.yellow.opacity(highlight ? 0.35 : 0))
                    .animation(
                        ReduceMotionFallback.animation(BrandMotion.pulse, reduced: reduceMotion),
                        value: highlight
                    )
            )
    }
}

// MARK: - SaleCompleteConfetti

private struct SaleCompleteConfettiModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    ZStack {
                        if !reduceMotion {
                            ConfettiView()
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        CheckmarkBadge()
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
            }
    }
}

private struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = (0..<40).map { _ in ConfettiParticle() }
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .position(
                        x: animate ? p.endX * geo.size.width : p.startX * geo.size.width,
                        y: animate ? p.endY * geo.size.height : p.startY * geo.size.height
                    )
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: 0.6).delay(p.delay),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let startX: CGFloat = 0.5
    let startY: CGFloat = 0.5
    let endX: CGFloat = CGFloat.random(in: 0...1)
    let endY: CGFloat = CGFloat.random(in: 0...1)
    let size: CGFloat = CGFloat.random(in: 6...12)
    let delay: Double = Double.random(in: 0...0.3)
    let color: Color = [.red, .orange, .yellow, .green, .blue, .purple].randomElement()!
}

private struct CheckmarkBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: 80, height: 80)
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Sale complete")
    }
}

// MARK: - SmsSentFlyIn

private struct SmsSentFlyInModifier: ViewModifier {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: appeared || reduceMotion ? 0 : 60)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(
                    ReduceMotionFallback.fadeOrFull(BrandMotion.appear, reduced: reduceMotion)
                ) {
                    appeared = true
                }
            }
    }
}

// MARK: - PaymentApprovedCheck

private struct PaymentApprovedCheckModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    CircleDrawCheckView(reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .accessibilityLabel("Payment approved")
                }
            }
    }
}

private struct CircleDrawCheckView: View {
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(-90))

            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.green)
                .opacity(progress >= 1 ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeInOut(duration: 0.5)) {
                    progress = 1
                }
            }
        }
    }
}

// MARK: - LowStockPulse

private struct LowStockPulseModifier: ViewModifier {
    let isActive: Bool
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isActive {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .scaleEffect(pulsing && !reduceMotion ? 1.5 : 1.0)
                        .opacity(pulsing && !reduceMotion ? 0.5 : 1.0)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: pulsing
                        )
                        .onAppear { pulsing = true }
                        .accessibilityLabel("Low stock")
                }
            }
    }
}

// MARK: - NewBadgePulse

/// Scale-pulse used on "new" badges and counters.
/// Spec §30.6: scale 1.0 ↔ 1.05 over 600ms, repeating.
/// Reduce Motion: no animation (badge still visible; only the pulse is suppressed).
private struct NewBadgePulseModifier: ViewModifier {
    let isActive: Bool
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing && !reduceMotion ? 1.05 : 1.0)
            .animation(
                isActive && !reduceMotion
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : nil,
                value: pulsing
            )
            .onAppear {
                if isActive && !reduceMotion { pulsing = true }
            }
            .onChange(of: isActive) { _, newValue in
                pulsing = newValue && !reduceMotion
            }
    }
}

// MARK: - Public View extensions

public extension View {

    /// Temporary highlight pulse on a new ticket row.
    ///
    /// - Parameter highlight: Set to `true` immediately after insertion; revert to `false` after ~1s.
    func ticketCreatedPulse(highlight: Bool) -> some View {
        modifier(TicketCreatedPulseModifier(highlight: highlight))
    }

    /// Full-screen confetti + center checkmark on sale completion.
    ///
    /// Reduce Motion: renders a static checkmark only (no confetti, no spring).
    func saleCompleteConfetti(isActive: Bool) -> some View {
        modifier(SaleCompleteConfettiModifier(isActive: isActive))
    }

    /// Slide-in from trailing edge when the view appears (SMS bubble fly-in).
    func smsSentFlyIn() -> some View {
        modifier(SmsSentFlyInModifier())
    }

    /// Animated circle-draw checkmark for payment approval.
    func paymentApprovedCheck(isActive: Bool) -> some View {
        modifier(PaymentApprovedCheckModifier(isActive: isActive))
    }

    /// Red badge pulse for low-stock state.
    func lowStockPulse(isActive: Bool) -> some View {
        modifier(LowStockPulseModifier(isActive: isActive))
    }

    /// Gentle scale pulse (1.0 ↔ 1.05, 600ms) for "new" badges.
    ///
    /// Spec §30.6. Pass `isActive: false` to stop pulsing once the user
    /// has acknowledged the badge. Reduce Motion: no animation.
    func newBadgePulse(isActive: Bool) -> some View {
        modifier(NewBadgePulseModifier(isActive: isActive))
    }
}
