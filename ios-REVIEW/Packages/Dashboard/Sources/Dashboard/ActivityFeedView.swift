import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §3.6 Recent activity feed

// MARK: - ViewModel

/// §3.6 — Loads the activity feed from `GET /api/v1/activity?limit=20`.
@MainActor
@Observable
public final class ActivityFeedViewModel {

    public enum State: Sendable {
        case idle, loading, loaded([ActivityEvent]), failed(String)
    }

    public var state: State = .idle
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let events = try await api.activityFeed(limit: 20)
            state = .loaded(events)
        } catch {
            AppLog.ui.error("ActivityFeed load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    public func reload() async {
        state = .idle
        await load()
    }
}

// MARK: - View

/// §3.6 — Chronological list of recent events under the KPI grid.
/// Collapsible, tap → deep-link.
public struct ActivityFeedView: View {
    @State private var vm: ActivityFeedViewModel
    @State private var isExpanded: Bool = true
    var onEventTap: ((ActivityEvent) -> Void)?

    public init(api: APIClient, onEventTap: ((ActivityEvent) -> Void)? = nil) {
        _vm = State(wrappedValue: ActivityFeedViewModel(api: api))
        self.onEventTap = onEventTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if isExpanded {
                bodyContent
            }
        }
        .task { await vm.load() }
    }

    private var sectionHeader: some View {
        HStack {
            Text("Recent activity")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                withAnimation(.spring(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse activity feed" : "Expand activity feed")
        }
        .padding(.bottom, BrandSpacing.sm)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch vm.state {
        case .idle, .loading:
            ActivityFeedSkeletonView()
        case .failed:
            HStack {
                Text("Couldn't load activity")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Button("Retry") { Task { await vm.reload() } }
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
                    .buttonStyle(.plain)
            }
            .padding(.vertical, BrandSpacing.sm)
        case .loaded(let events) where events.isEmpty:
            Text("No recent activity yet.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.vertical, BrandSpacing.sm)
        case .loaded(let events):
            VStack(spacing: 0) {
                ForEach(events) { event in
                    ActivityEventRow(event: event) {
                        onEventTap?(event)
                    }
                    if event.id != events.last?.id {
                        Divider().overlay(Color.bizarreOutline.opacity(0.15)).padding(.leading, 36)
                    }
                }
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5))
        }
    }
}

// MARK: - Event row

private struct ActivityEventRow: View {
    let event: ActivityEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconBackground(for: event.entityType))
                        .frame(width: 24, height: 24)
                    Image(systemName: systemIcon(for: event.entityType))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    HStack {
                        Text(event.title)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .lineLimit(1)
                        Spacer()
                        Text(relativeTime(from: event.occurredAt))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let subtitle = event.subtitle {
                        Text(subtitle)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = [event.title]
        if let subtitle = event.subtitle { parts.append(subtitle) }
        parts.append(relativeTime(from: event.occurredAt))
        return parts.joined(separator: ". ")
    }

    private func systemIcon(for entityType: String) -> String {
        switch entityType {
        case "ticket":   return "wrench.and.screwdriver"
        case "invoice":  return "doc.text"
        case "sms":      return "message"
        case "customer": return "person"
        case "payment":  return "dollarsign"
        default:         return "circle.fill"
        }
    }

    private func iconBackground(for entityType: String) -> Color {
        switch entityType {
        case "ticket":   return .bizarreOrange
        case "invoice":  return Color.blue
        case "sms":      return Color.green
        case "payment":  return Color.teal
        default:         return .bizarreOnSurfaceMuted
        }
    }

    private func relativeTime(from iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso8601) else {
            // Fallback: try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date2 = formatter.date(from: iso8601) else { return "" }
            return RelativeDateTimeFormatter().localizedString(for: date2, relativeTo: Date())
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Skeleton

private struct ActivityFeedSkeletonView: View {
    @State private var shimmer: Bool = false

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: BrandSpacing.sm) {
                    Circle()
                        .fill(Color.bizarreOutline.opacity(shimmer ? 0.4 : 0.2))
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreOutline.opacity(shimmer ? 0.4 : 0.2))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreOutline.opacity(shimmer ? 0.3 : 0.15))
                            .frame(width: 120, height: 10)
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .accessibilityLabel("Loading activity feed")
    }
}
