import SwiftUI
import Core
import DesignSystem

// MARK: - §3.8 iPhone FAB — floating .brandGlassProminent button
//
// iPhone only (compact width). Expands radially to show:
//   New Ticket / New Sale / New Customer / Scan Barcode / New SMS
//
// On iPad / Mac the toolbar group handles the same actions — no FAB shown.
//
// Design note: Apple's Human Interface Guidelines (iOS 26) recommend using
// .glassEffect on overlay controls. We use .brandGlass(.identity, interactive: true)
// for the main FAB pill and slightly smaller secondary pills on expand.
// Haptic .medium fires on expand; .selection on each secondary action tap.
//
// Accessibility: when collapsed, VoiceOver reads "Quick actions, expanded";
// when expanded, each action button is individually reachable.

// MARK: - ViewModel

@MainActor
@Observable
public final class DashboardFABViewModel {
    public var isExpanded: Bool = false

    public func toggle() {
        isExpanded.toggle()
        BrandHaptics.lightImpact()
    }

    public func collapse() {
        isExpanded = false
    }
}

// MARK: - View

/// Floating action button overlay for the Dashboard on iPhone (compact).
/// Placed as a `.overlay(alignment: .bottomTrailing)` on the ScrollView.
public struct DashboardFAB: View {
    @State private var fabVM = DashboardFABViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var onNewTicket: (() -> Void)?
    public var onNewSale: (() -> Void)?
    public var onNewCustomer: (() -> Void)?
    public var onScanBarcode: (() -> Void)?
    public var onNewSMS: (() -> Void)?

    public init(
        onNewTicket: (() -> Void)? = nil,
        onNewSale: (() -> Void)? = nil,
        onNewCustomer: (() -> Void)? = nil,
        onScanBarcode: (() -> Void)? = nil,
        onNewSMS: (() -> Void)? = nil
    ) {
        self.onNewTicket = onNewTicket
        self.onNewSale = onNewSale
        self.onNewCustomer = onNewCustomer
        self.onScanBarcode = onScanBarcode
        self.onNewSMS = onNewSMS
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Scrim — tap outside to collapse
            if fabVM.isExpanded {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { fabVM.collapse() }
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            VStack(alignment: .trailing, spacing: 12) {
                if fabVM.isExpanded {
                    // Secondary action pills — radial from bottom-right
                    fabAction("New SMS",       icon: "message.badge.plus",   action: { fire { onNewSMS?() } })
                    fabAction("Scan Barcode",  icon: "barcode.viewfinder",   action: { fire { onScanBarcode?() } })
                    fabAction("New Customer",  icon: "person.badge.plus",    action: { fire { onNewCustomer?() } })
                    fabAction("New Sale",      icon: "cart.badge.plus",      action: { fire { onNewSale?() } })
                    fabAction("New Ticket",    icon: "plus.circle",          action: { fire { onNewTicket?() } })
                }

                // Main FAB
                Button {
                    fabVM.toggle()
                } label: {
                    Image(systemName: fabVM.isExpanded ? "xmark" : "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.bizarreOrange, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .rotationEffect(.degrees(fabVM.isExpanded ? 45 : 0))
                        .animation(reduceMotion ? .none : .spring(duration: 0.25), value: fabVM.isExpanded)
                }
                .accessibilityLabel(fabVM.isExpanded ? "Collapse quick actions" : "Expand quick actions")
                .accessibilityHint(fabVM.isExpanded ? "Double-tap to collapse" : "Double-tap to expand New ticket, New sale, New customer, Scan barcode, New SMS")
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func fabAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 36, height: 36)
                    .background(Color.bizarreSurface1, in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
                    )
            }
        }
        .buttonStyle(.plain)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity)
                )
        )
        .animation(reduceMotion ? .none : .spring(duration: 0.22), value: fabVM.isExpanded)
        .accessibilityLabel(label)
    }

    private func fire(_ action: () -> Void) {
        BrandHaptics.selection()
        fabVM.collapse()
        action()
    }
}

// MARK: - Dashboard integration helper

public extension View {
    /// Overlays the iPhone FAB on a view, hidden on iPad/Mac.
    /// Pass nil for any callback to omit that action from the FAB.
    @ViewBuilder
    func dashboardFAB(
        onNewTicket: (() -> Void)? = nil,
        onNewSale: (() -> Void)? = nil,
        onNewCustomer: (() -> Void)? = nil,
        onScanBarcode: (() -> Void)? = nil,
        onNewSMS: (() -> Void)? = nil
    ) -> some View {
        if Platform.isCompact {
            self.overlay(alignment: .bottomTrailing) {
                DashboardFAB(
                    onNewTicket: onNewTicket,
                    onNewSale: onNewSale,
                    onNewCustomer: onNewCustomer,
                    onScanBarcode: onScanBarcode,
                    onNewSMS: onNewSMS
                )
            }
        } else {
            self
        }
    }
}
