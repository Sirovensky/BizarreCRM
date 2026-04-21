import ActivityKit
import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - Live Activity Widget declaration

/// Live Activity for in-progress POS sales.
///
/// Shows cart total and item count in the Dynamic Island and on the lock screen.
/// Start by calling `LiveActivityCoordinator.startSaleActivity(...)` from the POS flow.
/// Update via `LiveActivityCoordinator.updateSaleActivity(cartTotalCents:itemCount:)`.
/// End via `LiveActivityCoordinator.endSaleActivity()` on sale finalize or cancel.
struct SaleInProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: POSSaleActivityAttributes.self) { context in
            // Lock screen / StandBy presentation
            LockScreenSaleView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long press)
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.cashierName)
                            .font(.caption)
                            .accessibilityLabel("Cashier: \(context.attributes.cashierName)")
                    } icon: {
                        Image(systemName: "cart.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formattedCents(context.state.cartTotalCents))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Cart total: \(formattedCents(context.state.cartTotalCents))")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("\(context.state.itemCount) item\(context.state.itemCount == 1 ? "" : "s") in cart")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(context.state.itemCount) items in cart")
                        Spacer()
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
            } compactLeading: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } compactTrailing: {
                Text(formattedCents(context.state.cartTotalCents))
                    .font(.caption2.weight(.semibold))
                    .accessibilityLabel("Total: \(formattedCents(context.state.cartTotalCents))")
            } minimal: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Sale in progress")
            }
        }
    }

    private func formattedCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }
}

// MARK: - Lock screen view

private struct LockScreenSaleView: View {
    let context: ActivityViewContext<POSSaleActivityAttributes>

    var body: some View {
        HStack {
            Image(systemName: "cart.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Sale in Progress")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Sale in progress")

                Text("\(context.state.itemCount) item\(context.state.itemCount == 1 ? "" : "s") · \(formattedCents(context.state.cartTotalCents))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(context.state.itemCount) items, total \(formattedCents(context.state.cartTotalCents))")
            }

            Spacer()

            Link(destination: URL(string: "bizarrecrm://pos")!) {
                Text("Open POS")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Open POS")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.primary)
    }

    private func formattedCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }
}
