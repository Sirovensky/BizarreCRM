#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

/// §42.1 — Call log screen.
///
/// Layout:
/// - iPhone: `NavigationStack` with a searchable list.
/// - iPad: `NavigationSplitView` with a master list + detail placeholder.
///
/// 404 / comingSoon path: the view-model transitions to `.comingSoon` when the
/// server returns a 404. The view renders a "Coming soon" banner.
public struct CallLogView: View {

    @State private var viewModel: CallLogViewModel
    @State private var searchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var debouncedQuery: String = ""
    @State private var selectedCallId: Int64?

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        self._viewModel = State(initialValue: CallLogViewModel(api: api))
    }

    public var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                ipadLayout
            } else {
                iphoneLayout
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - iPhone layout

    private var iphoneLayout: some View {
        NavigationStack {
            contentBody
                .navigationTitle("Calls")
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        refreshButton
                    }
                }
        }
    }

    // MARK: - iPad layout

    private var ipadLayout: some View {
        NavigationSplitView {
            contentBody
                .navigationTitle("Calls")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        refreshButton
                    }
                }
        } detail: {
            Text("Select a call")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared content

    @ViewBuilder
    private var contentBody: some View {
        switch viewModel.state {
        case .loading:
            loadingView
        case .loaded:
            listView
        case .failed(let message):
            errorView(message: message)
        case .comingSoon:
            comingSoonView
        }
    }

    // MARK: - List

    private var listView: some View {
        let calls = viewModel.filteredCalls(debouncedQuery)
        return Group {
            if calls.isEmpty && debouncedQuery.isEmpty {
                emptyStateView
            } else {
                List(calls) { entry in
                    CallLogRow(entry: entry)
                        .swipeActions(edge: .trailing) {
                            Button {
                                CallQuickAction.placeCall(to: entry.phoneNumber)
                            } label: {
                                Label("Call back", systemImage: "phone.fill")
                            }
                            .tint(.green)
                        }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search by name or number")
                .onChange(of: searchText) { _, newValue in
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 300 ms
                        if !Task.isCancelled {
                            debouncedQuery = newValue
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        ProgressView("Loading calls…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading call log")
    }

    private var emptyStateView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "phone.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No calls yet")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No calls yet")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.xxxl)
            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.brandGlass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var comingSoonView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "phone.badge.clock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Coming soon")
                .font(.title3)
                .foregroundStyle(.primary)
            Text("Call history is not yet available on this server.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Call history coming soon")
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.load() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Refresh calls")
    }
}

// MARK: - CallLogRow

private struct CallLogRow: View {
    let entry: CallLogEntry

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            directionIcon
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(entry.customerName ?? entry.phoneNumber)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(entry.direction.capitalized)
                        .font(.caption)
                        .foregroundStyle(directionColor)
                    if let duration = entry.durationSeconds {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let ts = entry.startedAt {
                Text(relativeTimestamp(ts))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var directionIcon: some View {
        Image(systemName: entry.isInbound ? "phone.arrow.down.left" : "phone.arrow.up.right")
            .foregroundStyle(directionColor)
            .font(.system(size: 20))
            .frame(width: 32)
            .accessibilityHidden(true)
    }

    private var directionColor: Color {
        entry.isInbound ? .blue : .green
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    private func relativeTimestamp(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) ?? {
            let alt = ISO8601DateFormatter()
            alt.formatOptions = [.withInternetDateTime]
            return alt.date(from: iso)
        }() else { return iso }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var accessibilityLabel: String {
        let who = entry.customerName ?? entry.phoneNumber
        let dir = entry.isInbound ? "Inbound" : "Outbound"
        let dur = entry.durationSeconds.map { ", duration \(formatDuration($0))" } ?? ""
        return "\(dir) call \(entry.isInbound ? "from" : "to") \(who)\(dur)"
    }
}
#endif
