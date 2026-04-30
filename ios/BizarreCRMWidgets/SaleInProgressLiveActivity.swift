import ActivityKit
import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - Live Activity Widget declaration

/// Live Activity for in-progress POS sales.
///
/// Shows cart total, item count, and sale-workflow progress in the Dynamic Island
/// and on the lock screen. Progress drives from 0 (cart building) → 0.5 (payment
/// pending) → 1.0 (sale complete).
///
/// Start by calling `LiveActivityCoordinator.startSaleActivity(...)` from the POS flow.
/// Update via `LiveActivityCoordinator.updateSaleActivity(cartTotalCents:itemCount:progressPercent:)`.
/// End via `LiveActivityCoordinator.endSaleActivity(completed:)` — pass `completed: true`
/// so the lock-screen lingers 8 s with a "Sale complete" dismissal state.
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
                        Image(systemName: salePhaseIcon(context.state.progressPercent))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formattedCents(context.state.cartTotalCents))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Cart total: \(formattedCents(context.state.cartTotalCents))")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(context.state.itemCount) item\(context.state.itemCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("\(context.state.itemCount) items")
                            Spacer()
                            Text(salePhaseCopy(context.state.progressPercent))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tint)
                                .accessibilityLabel(salePhaseCopy(context.state.progressPercent))
                        }
                        // Sale-progress bar
                        ProgressView(value: context.state.progressPercent)
                            .tint(.tint)
                            .accessibilityLabel("Sale progress \(Int(context.state.progressPercent * 100)) percent")
                    }
                }
            } compactLeading: {
                // Phase icon changes as sale progresses (cart → card → checkmark)
                Image(systemName: salePhaseIcon(context.state.progressPercent))
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            } compactTrailing: {
                // Show total in compact trailing; suffix "✓" when payment complete
                if context.state.progressPercent >= 1.0 {
                    Label {
                        Text(formattedCents(context.state.cartTotalCents))
                            .font(.caption2.weight(.semibold))
                    } icon: {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.bizarreSuccess)
                    }
                    .accessibilityLabel("Sale complete, \(formattedCents(context.state.cartTotalCents))")
                } else {
                    Text(formattedCents(context.state.cartTotalCents))
                        .font(.caption2.weight(.semibold))
                        .accessibilityLabel("Total: \(formattedCents(context.state.cartTotalCents))")
                }
            } minimal: {
                Image(systemName: salePhaseIcon(context.state.progressPercent))
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

    /// SF Symbol representing the current sale phase.
    private func salePhaseIcon(_ progress: Double) -> String {
        switch progress {
        case 1.0...:           return "checkmark.circle.fill"
        case 0.5..<1.0:        return "creditcard.fill"
        default:               return "cart.fill"
        }
    }

    /// Short copy label for the expanded Dynamic Island bottom row.
    private func salePhaseCopy(_ progress: Double) -> String {
        switch progress {
        case 1.0...:    return "Complete"
        case 0.5..<1.0: return "Payment pending"
        default:        return "Building cart"
        }
    }
}

// MARK: - Lock screen view

private struct LockScreenSaleView: View {
    let context: ActivityViewContext<POSSaleActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: salePhaseIcon(context.state.progressPercent))
                    .font(.title2)
                    .foregroundStyle(context.state.progressPercent >= 1 ? .bizarreSuccess : .tint)
                    .accessibilityHidden(true)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    // Title: phase-aware copy
                    Text(context.state.progressPercent >= 1 ? "Sale Complete" : "Sale in Progress")
                        .font(.brandTitleSmall())
                        .foregroundStyle(context.state.progressPercent >= 1 ? .bizarreSuccess : .primary)
                        .accessibilityLabel(context.state.progressPercent >= 1 ? "Sale complete" : "Sale in progress")

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

            // Sale-progress bar — shows cart build → payment → complete lifecycle
            ProgressView(value: context.state.progressPercent)
                .tint(context.state.progressPercent >= 1 ? .bizarreSuccess : .tint)
                .accessibilityLabel("Sale progress \(Int(context.state.progressPercent * 100)) percent complete")
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

    private func salePhaseIcon(_ progress: Double) -> String {
        switch progress {
        case 1.0...:    return "checkmark.circle.fill"
        case 0.5..<1.0: return "creditcard.fill"
        default:        return "cart.fill"
        }
    }
}
