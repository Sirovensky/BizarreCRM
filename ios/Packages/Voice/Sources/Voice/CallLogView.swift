#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

/// §42.1 — Call log screen.
///
/// Layout:
/// - iPhone: `NavigationStack` with a searchable list + direction filter picker.
/// - iPad: `NavigationSplitView` (3-col): filter sidebar | call list | detail panel.
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
            if Platform.isIPad {
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
            VStack(spacing: 0) {
                directionPicker
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                contentBody
            }
            .navigationTitle("Calls")
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    refreshButton
                }
            }
        }
    }

    // MARK: - iPad 3-col layout: [filter sidebar | list | detail]

    private var ipadLayout: some View {
        NavigationSplitView {
            // Column 1 — Direction filter
            filterSidebar
                .navigationTitle("Filter")
                .navigationBarTitleDisplayMode(.inline)
        } content: {
            // Column 2 — Call list
            callListColumn
                .navigationTitle("Calls")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        refreshButton
                    }
                }
        } detail: {
            // Column 3 — Detail / placeholder
            callDetailColumn
        }
    }

    // MARK: - iPad filter sidebar

    private var filterSidebar: some View {
        List(CallLogViewModel.DirectionFilter.allCases, id: \.self, selection: Binding(
            get: { viewModel.directionFilter },
            set: { viewModel.directionFilter = $0 }
        )) { filter in
            Label {
                Text(filter.label)
            } icon: {
                Image(systemName: filterIcon(for: filter))
            }
            .tag(filter)
        }
        .listStyle(.sidebar)
    }

    // MARK: - iPad list column

    private var callListColumn: some View {
        contentBody
            .searchable(text: $searchText, prompt: "Search by name or number")
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled { debouncedQuery = newValue }
                }
            }
    }

    // MARK: - iPad detail column

    @ViewBuilder
    private var callDetailColumn: some View {
        if let id = selectedCallId,
           case .loaded(let calls) = viewModel.state,
           let entry = calls.first(where: { $0.id == id }) {
            CallDetailView(entry: entry)
        } else {
            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: "phone.badge.waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Select a call")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("No call selected")
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

    // MARK: - Direction picker (iPhone + injected into iPad list toolbar)

    private var directionPicker: some View {
        Picker("Direction", selection: Binding(
            get: { viewModel.directionFilter },
            set: { viewModel.directionFilter = $0 }
        )) {
            ForEach(CallLogViewModel.DirectionFilter.allCases, id: \.self) { f in
                Text(f.label).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Filter calls by direction")
    }

    // MARK: - List

    private var listView: some View {
        let calls = viewModel.filteredCalls(debouncedQuery)
        return Group {
            if calls.isEmpty && debouncedQuery.isEmpty {
                emptyStateView
            } else {
                List(calls, selection: $selectedCallId) { entry in
                    CallLogRow(entry: entry)
                        .tag(entry.id)
                        .swipeActions(edge: .trailing) {
                            Button {
                                CallQuickAction.placeCall(to: entry.phoneNumber)
                            } label: {
                                Label("Call back", systemImage: "phone.fill")
                            }
                            .tint(.green)
                        }
                        .hoverEffect(.highlight)
                        .contextMenu {
                            Button {
                                CallQuickAction.placeCall(to: entry.phoneNumber)
                            } label: {
                                Label("Call \(entry.customerName ?? entry.phoneNumber)", systemImage: "phone.fill")
                            }
                        }
                }
                .listStyle(.plain)
                // iPhone-only inline direction picker + search bar
                .if(!Platform.isIPad) { view in
                    view.searchable(text: $searchText, prompt: "Search by name or number")
                        .onChange(of: searchText) { _, newValue in
                            searchDebounceTask?.cancel()
                            searchDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                if !Task.isCancelled { debouncedQuery = newValue }
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
            Text("No calls")
                .font(.title3)
                .foregroundStyle(.secondary)
            if viewModel.directionFilter != .all {
                Text("No \(viewModel.directionFilter.label.lowercased()) calls found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No calls")
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

    // MARK: - Helpers

    private func filterIcon(for filter: CallLogViewModel.DirectionFilter) -> String {
        switch filter {
        case .all:      return "phone"
        case .inbound:  return "phone.arrow.down.left"
        case .outbound: return "phone.arrow.up.right"
        }
    }
}

// MARK: - View+if helper (file-private)

extension View {
    @ViewBuilder
    fileprivate func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - CallDetailView (iPad detail column)

private struct CallDetailView: View {
    let entry: CallLogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                // Header
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: entry.isInbound
                              ? "phone.arrow.down.left"
                              : "phone.arrow.up.right")
                            .font(.system(size: 32))
                            .foregroundStyle(entry.isInbound ? .blue : .green)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text(entry.customerName ?? entry.phoneNumber)
                                .font(.title2)
                                .fontWeight(.semibold)
                            if entry.customerName != nil {
                                Text(entry.phoneNumber)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, DesignTokens.Spacing.lg)

                // Meta
                metaSection

                // Transcript
                if let text = entry.transcriptText, !text.isEmpty {
                    transcriptSection(text)
                }

                // Call back button
                Button {
                    CallQuickAction.placeCall(to: entry.phoneNumber)
                } label: {
                    Label("Call back", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.brandGlass)
                .keyboardShortcut("c", modifiers: .command)
                .accessibilityLabel("Call back \(entry.customerName ?? entry.phoneNumber)")

                Spacer(minLength: DesignTokens.Spacing.huge)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxxl)
        }
        .navigationTitle(entry.customerName ?? entry.phoneNumber)
        .navigationBarTitleDisplayMode(.large)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            metaRow(label: "Direction", value: entry.direction.capitalized)
            if let dur = entry.durationSeconds {
                metaRow(label: "Duration", value: formatDuration(dur))
            }
            if let ts = entry.startedAt {
                metaRow(label: "Time", value: relativeTimestamp(ts))
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }

    private func transcriptSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Transcript")
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcript: \(text)")
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
