import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// §22.G — Custom iPad icon-rail sidebar.
//
// Design spec (from pos-ipad-mockups.html):
//   • 64 pt collapsed, 200 pt expanded
//   • Brand mark at top — tap to expand / collapse
//   • 8 item rows with 48×48 tap target, .railHoverEffect()
//   • Active item: cream-tinted pill (dark mode) / orange-tinted pill (light mode)
//   • Avatar at bottom — tap for operator context menu
//   • Auto-collapse after 30 s when expanded
//   • Reduce Motion: spring replaced with opacity fade
//
// NOTE: `@Environment(\.posTheme)` requires the DesignSystem package.
// The Core package does not yet import DesignSystem, so active-pill colours
// fall back to `Color.bizarreOrange` via a local protocol shim.
// TODO: Once Agent A's theme env is wired into Core (or Core gains a
//       DesignSystem dependency), replace the `_pillForeground` / `_pillBackground`
//       helpers with `theme.primary` / `theme.primarySoft`.

// MARK: - Platform-safe hover effect

private extension View {
    /// Applies `.hoverEffect(.highlight)` on UIKit platforms; no-op on macOS.
    @ViewBuilder
    func railHoverEffect() -> some View {
        #if canImport(UIKit)
        self.hoverEffect(.highlight)
        #else
        self
        #endif
    }
}

// MARK: - Auto-collapse timer

/// Notified when the expand timer fires. Modelled as a protocol so tests
/// can inject a mock without using real `DispatchQueue.main`.
@MainActor
protocol RailAutoCollapseTimer: AnyObject {
    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class DefaultRailAutoCollapseTimer: RailAutoCollapseTimer {
    private var task: Task<Void, Never>?

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

// MARK: - Rail button

private struct RailItemButton: View {
    let item: RailItem
    let isSelected: Bool
    let isExpanded: Bool
    let pillBackground: Color
    let pillForeground: Color
    /// §91.9-2: Optional 1pt outline drawn over the active pill in light mode.
    let pillOutlineColor: Color?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(pillBackground)
                        .frame(width: isExpanded ? 180 : 48, height: 48)
                        .overlay {
                            // §91.9 — light-mode outline so active pill reads against material.
                            if let outline = pillOutlineColor {
                                Capsule()
                                    .strokeBorder(outline, lineWidth: 1)
                            }
                        }
                        .animation(
                            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28),
                            value: isExpanded
                        )
                }

                HStack(alignment: .center, spacing: isExpanded ? 12 : 0) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isSelected ? pillForeground : Color.primary)
                            .frame(width: 28, height: 28)

                        if let badge = item.badge {
                            BadgeView(badge: badge)
                                .offset(x: 6, y: -6)
                        }
                    }

                    if isExpanded {
                        Text(item.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? pillForeground : Color.primary)
                            .lineLimit(1)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, isExpanded ? 14 : 0)
            }
            .frame(width: isExpanded ? 180 : 48, height: 48)
        }
        .buttonStyle(.plain)
        .frame(width: isExpanded ? 180 : 48, height: 48)
        .contentShape(Rectangle())
        .railHoverEffect()
        // §91.7-1: tooltip label visible on hover (Mac / iPadOS pointer)
        .help(item.title)
        // §91.7-2: VoiceOver label + selected state trait
        .accessibilityLabel(Text(item.title))
        .accessibilityHint(isSelected ? "Selected" : "Navigate to \(item.title)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Badge view

private struct BadgeView: View {
    let badge: Badge

    var body: some View {
        switch badge {
        case .dot:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Unread indicator")
        case .count(let n):
            Text(n < 100 ? "\(n)" : "99+")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
                .fixedSize()
                .accessibilityLabel("\(n) unread")
        }
    }
}

// MARK: - RailSidebarView

/// Custom 64 pt iPad icon-rail sidebar.
///
/// Usage:
/// ```swift
/// RailSidebarView(items: RailCatalog.primary, selection: $destination)
/// ```
///
/// Only renders on `.regular` horizontal size class.
/// iPhone callers remain on the existing `TabView` — `ShellLayout`
/// handles the branching.
@MainActor
public struct RailSidebarView: View {

    // MARK: - Configuration

    private let items: [RailItem]
    private let autoCollapseSeconds: TimeInterval
    private let timer: any RailAutoCollapseTimer

    // MARK: - State

    @Binding private var selection: RailDestination

    // §22 sidebar collapse persistence — last expand/collapse state survives
    // app restarts and scene reconnects.  Key is stable; no migration needed.
    @AppStorage("rail.sidebar.isExpanded") private var isExpanded: Bool = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Widths

    private let collapsedWidth: CGFloat = 64
    private let expandedWidth: CGFloat = 200

    // MARK: - Init

    /// Public init — uses the default real timer.
    public init(
        items: [RailItem],
        selection: Binding<RailDestination>,
        autoCollapseSeconds: TimeInterval = 30
    ) {
        self.items = items
        self._selection = selection
        self.autoCollapseSeconds = autoCollapseSeconds
        self.timer = DefaultRailAutoCollapseTimer()
    }

    /// Internal init for unit tests — allows injecting a fake timer.
    init(
        items: [RailItem],
        selection: Binding<RailDestination>,
        autoCollapseSeconds: TimeInterval = 30,
        timer: any RailAutoCollapseTimer
    ) {
        self.items = items
        self._selection = selection
        self.autoCollapseSeconds = autoCollapseSeconds
        self.timer = timer
    }

    // MARK: - Asset existence check

    private var brandMarkAssetExists: Bool {
        #if canImport(UIKit)
        return UIImage(named: "BrandMark") != nil
        #else
        return NSImage(named: "BrandMark") != nil
        #endif
    }

    // MARK: - Pill colours (TODO: replace with `theme.primary` / `theme.primarySoft` once Core
    //         imports DesignSystem and Agent A's posTheme env is available here)

    // §91.7-4 + §91.9-2: Saturated cream/orange fill so selected item reads against
    // .regularMaterial. Light mode pairs with the strokeBorder outline (above) for
    // unmistakable active state.
    private var pillBackground: Color {
        colorScheme == .dark
            ? Color(red: 253/255, green: 238/255, blue: 208/255, opacity: 0.30)  // cream
            : Color(red: 194/255, green: 65/255,  blue: 12/255,  opacity: 0.20)  // deep orange
    }

    /// §91.9-2 — light-mode outline color for active pill (nil in dark mode).
    private var pillOutlineColor: Color? {
        colorScheme == .light
            ? Color(red: 194/255, green: 65/255, blue: 12/255).opacity(0.85)
            : nil
    }

    private var pillForeground: Color {
        colorScheme == .dark
            ? Color(red: 253/255, green: 238/255, blue: 208/255)  // cream
            : Color(red: 194/255, green: 65/255,  blue: 12/255)   // deep orange
    }

    private var expandAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28)
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // --- Brand mark ---
            brandMark
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            // --- Scrollable items ---
            // §91.7-5: Items are grouped with subtle dividers between sections:
            //   Operations  — Dashboard, Tickets, Customers, POS, Inventory, SMS (indices 0–5)
            //   Reports     — Reports (index 6)
            //   Settings    — Settings (index 7)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .center, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // Insert divider before Reports group (index 6)
                        // and before Settings group (index 7).
                        if index == 6 || index == 7 {
                            Divider()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }

                        RailItemButton(
                            item: item,
                            isSelected: selection == item.destination,
                            isExpanded: isExpanded,
                            pillBackground: pillBackground,
                            pillForeground: pillForeground,
                            pillOutlineColor: pillOutlineColor
                        ) {
                            selection = item.destination
                            AppLog.ui.debug("Rail selected: \(item.destination.rawValue)")
                        }
                        .keyboardShortcut(
                            keyEquivalent(for: index),
                            modifiers: .command
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Divider()
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            // --- Avatar ---
            avatarButton
                .padding(.bottom, 16)
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .animation(expandAnimation, value: isExpanded)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation rail")
    }

    // MARK: - Brand mark

    @ViewBuilder
    private var brandMark: some View {
        Button {
            withAnimation(expandAnimation) {
                isExpanded.toggle()
            }
            if isExpanded {
                timer.schedule(after: autoCollapseSeconds) {
                    isExpanded = false
                }
            } else {
                timer.cancel()
            }
        } label: {
            Group {
                if brandMarkAssetExists {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                } else {
                    // Fallback: coloured circle with "B" when asset is absent
                    ZStack {
                        Circle()
                            .fill(pillForeground)
                            .frame(width: 32, height: 32)
                        Text("B")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(
                                colorScheme == .dark
                                    ? Color(red: 43/255, green: 20/255, blue: 0)
                                    : .white
                            )
                    }
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .railHoverEffect()
        .accessibilityLabel(isExpanded ? "Collapse navigation rail" : "Expand navigation rail")
        .accessibilityHint("Double-tap to \(isExpanded ? "collapse" : "expand")")
    }

    // MARK: - Avatar button

    @ViewBuilder
    private var avatarButton: some View {
        Menu {
            Button {
                AppLog.ui.info("Rail: switch user tapped")
            } label: {
                Label("Switch User", systemImage: "arrow.left.arrow.right")
            }

            Button {
                AppLog.ui.info("Rail: lock tapped")
            } label: {
                Label("Lock", systemImage: "lock")
            }

            Divider()

            Button(role: .destructive) {
                AppLog.ui.info("Rail: sign out tapped")
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(pillForeground.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(pillForeground)
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .menuStyle(.automatic)
        .railHoverEffect()
        .accessibilityLabel("Operator menu")
        .accessibilityHint("Opens switch user, lock, and sign out options")
    }

    // MARK: - Keyboard shortcuts (⌘1–⌘8)

    private func keyEquivalent(for index: Int) -> KeyEquivalent {
        let chars: [Character] = ["1","2","3","4","5","6","7","8"]
        let ch = index < chars.count ? chars[index] : Character(UnicodeScalar(49 + index)!)
        return KeyEquivalent(ch)
    }
}

// MARK: - Previews

#if DEBUG
import SwiftUI

#Preview("Rail — collapsed dark") {
    @Previewable @State var dest: RailDestination = .dashboard
    HStack(spacing: 0) {
        RailSidebarView(items: RailCatalog.primary, selection: $dest)
        Divider()
        Text("Content area — \(dest.rawValue)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .preferredColorScheme(.dark)
}

#Preview("Rail — collapsed light") {
    @Previewable @State var dest: RailDestination = .pos
    HStack(spacing: 0) {
        RailSidebarView(items: RailCatalog.primary, selection: $dest)
        Divider()
        Text("Content area — \(dest.rawValue)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .preferredColorScheme(.light)
}
#endif
