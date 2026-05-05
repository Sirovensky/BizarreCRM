import SwiftUI

/// Sanctioned brand motif — only use under Login wordmark, above Dashboard
/// greeting, and above TicketSuccess checkmark. Anywhere else is brand abuse.
public struct WaveDivider: View {
    public init() {}

    public var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addCurve(
                to: CGPoint(x: size.width, y: size.height / 2),
                control1: CGPoint(x: size.width * 0.33, y: 0),
                control2: CGPoint(x: size.width * 0.66, y: size.height)
            )
            ctx.stroke(
                path,
                with: .linearGradient(
                    .init(colors: [
                        Color.bizarreOrange.opacity(0.6),
                        Color.bizarreMagenta.opacity(0.3)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: 1.5
            )
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}
