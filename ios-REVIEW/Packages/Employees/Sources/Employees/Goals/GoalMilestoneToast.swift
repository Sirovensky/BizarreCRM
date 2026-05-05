import SwiftUI
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

// MARK: - GoalMilestoneToast

/// Toast that fires at 50 / 75 / 100% milestones.
/// Confetti is shown only on 100% and only when Reduce Motion is OFF.
public struct GoalMilestoneToast: View {
    public let milestone: Int      // 50, 75, or 100
    public let goalLabel: String
    public let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(milestone: Int, goalLabel: String, isPresented: Bool) {
        self.milestone = milestone
        self.goalLabel = goalLabel
        self.isPresented = isPresented
    }

    private var message: String {
        switch milestone {
        case 100: return "Goal achieved! \(goalLabel)"
        case 75:  return "75% there — keep going!"
        case 50:  return "Halfway to \(goalLabel)"
        default:  return "\(milestone)% milestone!"
        }
    }

    private var icon: String {
        switch milestone {
        case 100: return "star.fill"
        case 75:  return "flame.fill"
        default:  return "chart.line.uptrend.xyaxis"
        }
    }

    private var toastColor: Color {
        milestone == 100 ? .green : .orange
    }

    public var body: some View {
        if isPresented {
            ZStack {
                if milestone == 100 && !reduceMotion {
                    ConfettiView()
                        .allowsHitTesting(false)
                }
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: icon)
                        .foregroundStyle(toastColor)
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.md)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .shadow(radius: 8)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(BrandMotion.sheet, value: isPresented)
            .accessibilityLabel(message)
        }
    }
}

// MARK: - ConfettiView

// Confetti is only available on UIKit platforms (iPhone/iPad).
#if canImport(UIKit)
/// Lightweight confetti using CAEmitterLayer — only instantiated when
/// UIKit is available and Reduce Motion is off.
struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: UIScreen.main.bounds.midX, y: -10)
        emitter.emitterSize = CGSize(width: UIScreen.main.bounds.width, height: 1)

        let colors: [UIColor] = [.systemGreen, .systemOrange, .systemYellow, .systemBlue, .systemPink]
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.birthRate = 6
            cell.lifetime = 3.5
            cell.velocity = 200
            cell.velocityRange = 80
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 4
            cell.spin = 3
            cell.spinRange = 3
            cell.scaleRange = 0.5
            cell.scale = 0.3
            cell.color = color.cgColor
            cell.contents = UIImage(systemName: "circle.fill")?
                .withTintColor(color).cgImage
            return cell
        }
        view.layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            emitter.birthRate = 0
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#else
struct ConfettiView: View {
    var body: some View { EmptyView() }
}
#endif
