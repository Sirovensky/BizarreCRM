#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.7 — Ticket timeline view.
//
// Renders the event history as a vertical timeline with circle-dot +
// line connectors. Each row shows:
//   - An SF Symbol icon specific to the event kind.
//   - Actor name + timestamp.
//   - Event message.
//   - Optional diff chips (from/to for status changes).
//
// Accessibility:
//   - Each row is an accessibility element with combined label:
//     "<actorName> <message> at <timestamp>".
//   - Connector lines are hidden from VoiceOver.
//
// Reduce Motion: the connector line fade-in animation is muted when
// `.accessibilityReduceMotion` is true.

public struct TicketTimelineView: View {
    @State private var vm: TicketTimelineViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared: Bool = false

    public init(ticketId: Int64, api: APIClient, fallbackHistory: [TicketDetail.TicketHistory] = []) {
        _vm = State(wrappedValue: TicketTimelineViewModel(
            ticketId: ticketId,
            api: api,
            fallbackHistory: fallbackHistory
        ))
    }

    public var body: some View {
        Group {
            switch vm.loadState {
            case .idle, .loading:
                loadingView
            case .loaded:
                loadedView
            case .failed(let message):
                failedView(message)
            }
        }
        .task { await vm.load() }
    }

    // MARK: — Loading

    private var loadingView: some View {
        VStack(spacing: BrandSpacing.md) {
            ProgressView()
            Text("Loading timeline…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xl)
        .accessibilityLabel("Loading timeline")
    }

    // MARK: — Loaded

    private var loadedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterBar
                .padding(.bottom, BrandSpacing.sm)

            if vm.events.isEmpty {
                emptyState
            } else {
                timelineList
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                filterChip(label: "All", kind: nil)
                filterChip(label: "Status", kind: .statusChange)
                filterChip(label: "Notes", kind: .noteAdded)
                filterChip(label: "Photos", kind: .photoAdded)
                filterChip(label: "Assign", kind: .assigned)
                filterChip(label: "Parts", kind: .partOrdered)
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    private func filterChip(label: String, kind: TicketEvent.EventKind?) -> some View {
        let isActive = vm.filterKind == kind
        return Button {
            withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                vm.filterKind = kind
            }
        } label: {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(isActive ? .white : .bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .background(
                    isActive ? Color.bizarreOrange : Color.bizarreSurface2,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter: \(label)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var timelineList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(vm.events.enumerated()), id: \.element.id) { index, event in
                TimelineEventRow(
                    event: event,
                    isLast: index == vm.events.count - 1,
                    reduceMotion: reduceMotion,
                    appeared: appeared
                )
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .onAppear {
            if !reduceMotion {
                withAnimation(BrandMotion.listInsert) { appeared = true }
            } else {
                appeared = true
            }
        }
    }

    // MARK: — Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No events yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Timeline events will appear here as the ticket progresses.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No events yet. Timeline events will appear here as the ticket progresses.")
    }

    // MARK: — Failed

    private func failedView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load timeline")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") {
                Task { await vm.retry() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Couldn't load timeline: \(message)")
    }
}

// MARK: - Timeline event row

private struct TimelineEventRow: View {
    let event: TicketEvent
    let isLast: Bool
    let reduceMotion: Bool
    let appeared: Bool

    private let dotSize: CGFloat = 10
    private let lineWidth: CGFloat = 2
    private let lineColor = Color.bizarreOutline.opacity(0.5)

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            // Connector column
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .overlay(
                        Circle().strokeBorder(dotColor.opacity(0.3), lineWidth: 2)
                            .padding(-3)
                    )
                    .padding(.top, 4)

                if !isLast {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: lineWidth)
                        .frame(maxHeight: .infinity)
                        .opacity(appeared ? 1 : 0)
                        .animation(
                            reduceMotion ? .none : BrandMotion.listInsert.delay(0.1),
                            value: appeared
                        )
                }
            }
            .frame(width: dotSize + 8)
            .accessibilityHidden(true)

            // Content column
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                // Header row: icon + actor + timestamp
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: event.kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)

                    if let actor = event.actorName, !actor.isEmpty {
                        Text(actor)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }

                    Spacer()

                    Text(shortTimestamp(event.createdAt))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }

                // Message
                if !event.message.isEmpty {
                    Text(event.message)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Diff chips (status change from → to)
                if let diff = event.diff, !diff.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: BrandSpacing.xs) {
                            ForEach(diff, id: \.field) { entry in
                                DiffChip(entry: entry)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.bottom, BrandSpacing.base)
        }
        // Accessibility: combine entire row into a single element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: — Private

    private var dotColor: Color {
        switch event.kind {
        case .statusChange:  return .bizarreOrange
        case .noteAdded:     return .bizarreTeal
        case .photoAdded:    return .bizarreTeal
        case .assigned:      return Color.purple
        case .partOrdered:   return .bizarreError
        case .created:       return .bizarreSuccess
        case .invoiced:      return Color.indigo
        case .unknown:       return .bizarreOnSurfaceMuted
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let actor = event.actorName, !actor.isEmpty {
            parts.append(actor)
        }
        if !event.message.isEmpty {
            parts.append(event.message)
        }
        parts.append("at \(shortTimestamp(event.createdAt))")
        return parts.joined(separator: " — ")
    }

    private func shortTimestamp(_ iso: String) -> String {
        // Try to produce a short "Apr 20, 14:32" format.
        let prefix = String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
        return prefix
    }
}

// MARK: - Diff chip

private struct DiffChip: View {
    let entry: TicketEvent.DiffEntry

    var body: some View {
        HStack(spacing: 4) {
            if let from = entry.from {
                Text(from)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            if entry.from != nil && entry.to != nil {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            if let to = entry.to {
                Text(to)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, 2)
        .background(Color.bizarreSurface2, in: Capsule())
        .accessibilityLabel(diffAccessibilityLabel)
    }

    private var diffAccessibilityLabel: String {
        let field = entry.field.isEmpty ? "field" : entry.field
        if let from = entry.from, let to = entry.to {
            return "\(field) changed from \(from) to \(to)"
        }
        if let to = entry.to { return "\(field) set to \(to)" }
        return field
    }
}
#endif
