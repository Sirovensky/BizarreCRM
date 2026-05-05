import SwiftUI
import Core

// MARK: - DeepLinkDebugOverlay
//
// §65 — Debug-build overlay that surfaces deep-link state without launching
// a separate tool.
//
// Features:
//   - Last N routes from RouteHistory (scrollable breadcrumb list).
//   - Pending restore from LastRouteStore (persisted across cold launch).
//   - One-tap "copy URL" per history entry.
//   - Real-time `pending` route from DeepLinkRouter.
//   - Collapsible floating panel; only visible in DEBUG builds.
//
// Integration:
//   Attach to RootView (or any persistent container view) via the
//   `.deepLinkDebugOverlay()` view modifier.  The overlay is stripped from
//   release builds by the `#if DEBUG` guard — zero binary impact in App Store
//   distributions.
//
// Example:
//   ```swift
//   RootView()
//       .deepLinkDebugOverlay()
//   ```

#if DEBUG

// MARK: - View modifier convenience

extension View {
    /// Attaches the deep-link debug overlay to this view.
    /// No-op in non-DEBUG builds.
    public func deepLinkDebugOverlay() -> some View {
        self.overlay(alignment: .bottomTrailing) {
            DeepLinkDebugOverlay()
                .padding(12)
        }
    }
}

// MARK: - Overlay view

@MainActor
struct DeepLinkDebugOverlay: View {

    @State private var isExpanded = false
    @State private var historyEntries: [RouteHistory.Entry] = []
    @State private var pendingRestore: String? = nil
    @Environment(DeepLinkRouter.self) private var router

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if isExpanded {
                expandedPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            collapseButton
        }
        .animation(.spring(duration: 0.25), value: isExpanded)
        .task {
            await refreshHistory()
        }
    }

    // MARK: - Collapse button

    private var collapseButton: some View {
        Button {
            isExpanded.toggle()
            if isExpanded {
                Task { await refreshHistory() }
            }
        } label: {
            Label(
                isExpanded ? "Close" : "Deep Links",
                systemImage: isExpanded ? "xmark.circle.fill" : "link.badge.plus"
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .padding(10)
            .background(Color.accentColor.opacity(0.85), in: Circle())
            .shadow(radius: 4)
        }
        .accessibilityLabel(isExpanded ? "Close deep-link debug overlay" : "Open deep-link debug overlay")
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Header
            Text("Deep-Link Debug")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            Divider()

            // Current pending route
            pendingSection

            // Last-route restore candidate
            restoreSection

            // Route history
            historySection
        }
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 8)
    }

    // MARK: - Sections

    @ViewBuilder
    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Pending route", systemImage: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            if let pending = router.pending {
                Text(routeLabel(pending))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
            } else {
                Text("none")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
            }
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Cold-launch restore", systemImage: "bolt.horizontal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            if let restore = pendingRestore {
                Text(restore)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
            } else {
                Text("none stored")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Route history (last 10)", systemImage: "list.bullet.rectangle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            if historyEntries.isEmpty {
                Text("no routes yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(historyEntries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private func historyRow(_ entry: RouteHistory.Entry) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.destination.breadcrumbLabel)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                Text(entry.arrivedAt, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            // Copy URL button
            if let url = DeepLinkBuilder.build(entry.destination, form: .customScheme) {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Copy deep-link URL")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    /// Human-readable label for a `DeepLinkRoute` value (the legacy router type).
    private func routeLabel(_ route: DeepLinkRoute) -> String {
        switch route {
        case .dashboard(let tenantSlug):
            return "dashboard · \(tenantSlug)"
        case .ticket(let tenantSlug, let id):
            return "ticket \(id) · \(tenantSlug)"
        case .customer(let tenantSlug, let id):
            return "customer \(id) · \(tenantSlug)"
        case .invoice(let tenantSlug, let id):
            return "invoice \(id) · \(tenantSlug)"
        case .estimate(let tenantSlug, let id):
            return "estimate \(id) · \(tenantSlug)"
        case .lead(let tenantSlug, let id):
            return "lead \(id) · \(tenantSlug)"
        case .appointment(let tenantSlug, let id):
            return "appt \(id) · \(tenantSlug)"
        case .inventory(let tenantSlug, let sku):
            return "inventory \(sku) · \(tenantSlug)"
        case .smsThread(let tenantSlug, let threadID):
            return "sms \(threadID) · \(tenantSlug)"
        case .reports(let tenantSlug, let name):
            return "report \(name) · \(tenantSlug)"
        case .posRoot(let tenantSlug):
            return "pos · \(tenantSlug)"
        case .posNewCart(let tenantSlug):
            return "pos/new · \(tenantSlug)"
        case .posReturn(let tenantSlug):
            return "pos/return · \(tenantSlug)"
        case .settings(let tenantSlug, let section):
            return "settings/\(section ?? "root") · \(tenantSlug)"
        case .auditLogs(let tenantSlug):
            return "audit · \(tenantSlug)"
        case .search(let tenantSlug, let query):
            return "search \"\(query ?? "")\" · \(tenantSlug)"
        case .notifications(let tenantSlug):
            return "notifications · \(tenantSlug)"
        case .timeclock(let tenantSlug):
            return "timeclock · \(tenantSlug)"
        case .magicLink:
            return "magic-link"
        case .resetPassword:
            return "reset-password"
        case .setupInvite:
            return "setup-invite"
        case .safariExternal(let url):
            return "external: \(url.host ?? url.path)"
        case .unknown(let url):
            return "unknown: \(url.path)"
        }
    }

    // MARK: - Data refresh

    private func refreshHistory() async {
        let tail = await RouteHistory.shared.tail(10)
        historyEntries = tail
        pendingRestore = LastRouteStore.peek().map { $0.breadcrumbLabel }
    }
}

// MARK: - Preview

#Preview {
    Color.gray.opacity(0.2)
        .ignoresSafeArea()
        .deepLinkDebugOverlay()
        .environment(DeepLinkRouter.shared)
}

#endif // DEBUG
