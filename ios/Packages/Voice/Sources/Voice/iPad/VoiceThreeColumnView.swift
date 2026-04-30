/// §22 — Sidebar tab selection for `VoiceThreeColumnView`.
///
/// Declared as a top-level type (not nested) so macOS test targets can reference
/// it without UIKit (the view itself is UIKit-only).
public enum VoiceSidebarTab: String, CaseIterable, Identifiable {
    case calls     = "calls"
    case voicemail = "voicemail"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .calls:     return "Calls"
        case .voicemail: return "Voicemail"
        }
    }

    public var icon: String {
        switch self {
        case .calls:     return "phone"
        case .voicemail: return "voicemail"
        }
    }
}

#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

/// §22 — iPad-exclusive three-column Voice hub.
///
/// Column layout: **direction sidebar | voicemail/call list | detail + inline player**
///
/// This view is *separate* from the wave-4 `CallLogView`. It bundles the call
/// log and voicemail list behind a sidebar tab switcher so the user can navigate
/// between the two collections without leaving the three-column chrome. The
/// detail column embeds `VoicemailInlinePlayer` for voicemails and the existing
/// `CallDetailPanel` for calls.
///
/// Keyboard shortcuts wired here:
/// - ⌘F — activates the search field in the active list column.
/// - ⌘C — calls back the selected entry (if any).
/// - Space — forwarded to the inline player when a voicemail is selected.
///
/// Liquid Glass chrome:
/// - Navigation bars use `.toolbarBackground(.visible)` + glass badge for
///   unheard voicemail count.
/// - The sidebar uses `.listStyle(.sidebar)` (native glass tray on iPadOS 18+).
/// - Context menus on list rows use `VoiceContextMenu`.
public struct VoiceThreeColumnView: View {

    // MARK: - State

    @State private var callViewModel: CallLogViewModel
    @State private var voicemailViewModel: VoicemailViewModel
    @State private var selectedTab: VoiceSidebarTab = .calls
    @State private var selectedCallId: Int64?
    @State private var selectedVoicemailId: Int64?
    @State private var searchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var debouncedQuery: String = ""
    @State private var searchFocused: Bool = false

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
        self._callViewModel = State(initialValue: CallLogViewModel(api: api))
        self._voicemailViewModel = State(initialValue: VoicemailViewModel(api: api))
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView {
            sidebarColumn
        } content: {
            listColumn
        } detail: {
            detailColumn
        }
        .task { await callViewModel.load() }
        .task { await voicemailViewModel.load() }
        // ⌘F — focus search
        .voiceSearchShortcut {
            searchFocused = true
        }
        // ⌘C — callback selected entry
        .voiceCallbackShortcut {
            callbackSelectedEntry()
        }
    }

    // MARK: - Column 1: Sidebar

    private var sidebarColumn: some View {
        List {
            ForEach(VoiceSidebarTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    HStack {
                        Label(tab.label, systemImage: tab.icon)
                        Spacer()
                        if tab == .voicemail, let badge = unheardBadge {
                            badge
                        }
                        if selectedTab == tab {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var unheardBadge: BrandGlassBadge? {
        guard case .loaded(let items) = voicemailViewModel.state else { return nil }
        let count = items.filter { !$0.heard }.count
        guard count > 0 else { return nil }
        return BrandGlassBadge("\(count)", variant: .identity, tint: .blue)
    }

    // MARK: - Column 2: List

    @ViewBuilder
    private var listColumn: some View {
        switch selectedTab {
        case .calls:
            callListColumn
        case .voicemail:
            voicemailListColumn
        }
    }

    // Call list column
    private var callListColumn: some View {
        Group {
            switch callViewModel.state {
            case .loading:
                loadingView(label: "Loading calls…")
            case .loaded:
                callList
            case .failed(let msg):
                errorView(message: msg) { Task { await callViewModel.load() } }
            case .comingSoon:
                comingSoonView(
                    icon: "phone.badge.clock.fill",
                    message: "Call history is not yet available on this server."
                )
            }
        }
        .navigationTitle("Calls")
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(
            text: $searchText,
            isPresented: $searchFocused,
            prompt: "Search by name or number"
        )
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled { debouncedQuery = newValue }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                directionFilterMenu
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                refreshButton { Task { await callViewModel.load() } }
            }
        }
    }

    @ViewBuilder
    private var callList: some View {
        let calls = callViewModel.filteredCalls(debouncedQuery)
        if calls.isEmpty {
            emptyStateView(icon: "phone.slash", message: "No calls")
        } else {
            List(calls, selection: $selectedCallId) { entry in
                CallListRow(entry: entry)
                    .tag(entry.id)
                    .hoverEffect(.highlight)
                    .voiceContextMenu(
                        entry: entry,
                        onAddToCustomer: nil,  // host navigates to Customers
                        onArchive: nil          // not supported for calls
                    )
            }
            .listStyle(.plain)
        }
    }

    // Voicemail list column
    private var voicemailListColumn: some View {
        Group {
            switch voicemailViewModel.state {
            case .loading:
                loadingView(label: "Loading voicemails…")
            case .loaded(let items):
                if items.isEmpty {
                    emptyStateView(icon: "voicemail", message: "No voicemails")
                } else {
                    voicemailList(items)
                }
            case .failed(let msg):
                errorView(message: msg) { Task { await voicemailViewModel.load() } }
            case .comingSoon:
                comingSoonView(
                    icon: "voicemail.badge.clock.fill",
                    message: "Voicemail is not yet available on this server."
                )
            }
        }
        .navigationTitle("Voicemail")
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                refreshButton { Task { await voicemailViewModel.load() } }
            }
        }
    }

    private func voicemailList(_ items: [VoicemailEntry]) -> some View {
        List(items, selection: $selectedVoicemailId) { entry in
            VoicemailListRow(entry: entry)
                .tag(entry.id)
                .hoverEffect(.highlight)
                .voiceContextMenu(
                    entry: entry,
                    onAddToCustomer: nil,
                    onArchive: {
                        // Best-effort: mark heard acts as the soft-archive
                        Task { await voicemailViewModel.markHeard(entry: entry) }
                    }
                )
        }
        .listStyle(.plain)
    }

    // MARK: - Column 3: Detail

    @ViewBuilder
    private var detailColumn: some View {
        switch selectedTab {
        case .calls:
            callDetailColumn
        case .voicemail:
            voicemailDetailColumn
        }
    }

    @ViewBuilder
    private var callDetailColumn: some View {
        if let id = selectedCallId,
           case .loaded(let calls) = callViewModel.state,
           let entry = calls.first(where: { $0.id == id }) {
            CallDetailPanel(entry: entry)
        } else {
            placeholderDetail(
                icon: "phone.badge.waveform",
                message: "Select a call"
            )
        }
    }

    @ViewBuilder
    private var voicemailDetailColumn: some View {
        if let id = selectedVoicemailId,
           case .loaded(let items) = voicemailViewModel.state,
           let entry = items.first(where: { $0.id == id }) {
            VoicemailDetailPanel(entry: entry) {
                Task { await voicemailViewModel.markHeard(entry: entry) }
            }
            // Space bar — play/pause via the inline player inside the panel
            .voicePlayPauseShortcut {
                // Shortcut is also wired directly on VoicemailInlinePlayer;
                // this outer binding serves as a fallback for the detail column.
            }
        } else {
            placeholderDetail(
                icon: "voicemail",
                message: "Select a voicemail"
            )
        }
    }

    // MARK: - Toolbar helpers

    private var directionFilterMenu: some View {
        Menu {
            ForEach(CallLogViewModel.DirectionFilter.allCases, id: \.self) { filter in
                Button {
                    callViewModel.directionFilter = filter
                } label: {
                    HStack {
                        Text(filter.label)
                        if callViewModel.directionFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter calls by direction")
    }

    private func refreshButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Refresh")
    }

    // MARK: - Callback shortcut

    private func callbackSelectedEntry() {
        switch selectedTab {
        case .calls:
            if let id = selectedCallId,
               case .loaded(let calls) = callViewModel.state,
               let entry = calls.first(where: { $0.id == id }) {
                CallQuickAction.placeCall(to: entry.phoneNumber)
            }
        case .voicemail:
            if let id = selectedVoicemailId,
               case .loaded(let items) = voicemailViewModel.state,
               let entry = items.first(where: { $0.id == id }) {
                CallQuickAction.placeCall(to: entry.phoneNumber)
            }
        }
    }

    // MARK: - Shared sub-views

    private func loadingView(label: String) -> some View {
        ProgressView(label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(label)
    }

    private func emptyStateView(icon: String, message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private func errorView(message: String, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.xxxl)
            Button("Try again", action: onRetry)
                .buttonStyle(.brandGlass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func comingSoonView(icon: String, message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Coming soon")
                .font(.title3)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func placeholderDetail(icon: String, message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(message)
    }
}

// MARK: - CallListRow

private struct CallListRow: View {
    let entry: CallLogEntry

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: entry.isInbound ? "phone.arrow.down.left" : "phone.arrow.up.right")
                .foregroundStyle(entry.isInbound ? Color.blue : Color.green)
                .font(.system(size: 20))
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(entry.customerName ?? entry.phoneNumber)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(entry.direction.capitalized)
                        .font(.caption)
                        .foregroundStyle(entry.isInbound ? Color.blue : Color.green)
                    if let dur = entry.durationSeconds {
                        Text("·").font(.caption).foregroundStyle(.secondary)
                        Text(formatDuration(dur))
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
    }

    private func formatDuration(_ s: Int) -> String {
        s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60 == 0 ? "" : "\(s % 60)s")".trimmingCharacters(in: .whitespaces)
    }

    private func relativeTimestamp(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) ?? {
            let alt = ISO8601DateFormatter(); alt.formatOptions = [.withInternetDateTime]
            return alt.date(from: iso)
        }() else { return iso }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - VoicemailListRow

private struct VoicemailListRow: View {
    let entry: VoicemailEntry

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(entry.heard ? Color.secondary : Color.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack {
                    Text(entry.customerName ?? entry.phoneNumber)
                        .font(.body)
                        .fontWeight(entry.heard ? .regular : .semibold)
                        .lineLimit(1)
                    if !entry.heard {
                        Circle().fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Unheard")
                    }
                }
                if let ts = entry.receivedAt {
                    Text(relativeTimestamp(ts))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let dur = entry.durationSeconds {
                Text(formatDuration(dur))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func formatDuration(_ s: Int) -> String {
        s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60 == 0 ? "" : "\(s % 60)s")".trimmingCharacters(in: .whitespaces)
    }

    private func relativeTimestamp(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) ?? {
            let alt = ISO8601DateFormatter(); alt.formatOptions = [.withInternetDateTime]
            return alt.date(from: iso)
        }() else { return iso }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - CallDetailPanel

private struct CallDetailPanel: View {
    let entry: CallLogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                // Header
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: entry.isInbound ? "phone.arrow.down.left" : "phone.arrow.up.right")
                        .font(.system(size: 32))
                        .foregroundStyle(entry.isInbound ? Color.blue : Color.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(entry.customerName ?? entry.phoneNumber)
                            .font(.title2)
                            .fontWeight(.semibold)
                        if entry.customerName != nil {
                            Text(entry.phoneNumber)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, DesignTokens.Spacing.lg)

                // Meta card
                metaSection

                // Transcript
                if let text = entry.transcriptText, !text.isEmpty {
                    transcriptCard(text)
                }

                // Callback CTA
                Button {
                    CallQuickAction.placeCall(to: entry.phoneNumber)
                } label: {
                    Label("Call back", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.brandGlass)
                .keyboardShortcut(VoiceShortcut.callback, modifiers: VoiceShortcut.commandModifiers)
                .accessibilityLabel("Call back \(entry.customerName ?? entry.phoneNumber)")

                Spacer(minLength: DesignTokens.Spacing.huge)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxxl)
        }
        .navigationTitle(entry.customerName ?? entry.phoneNumber)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            metaRow("Direction", value: entry.direction.capitalized)
            if let dur = entry.durationSeconds {
                metaRow("Duration", value: formatDuration(dur))
            }
            if let ts = entry.startedAt {
                metaRow("Time", value: relativeTimestamp(ts))
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
        )
    }

    private func metaRow(_ label: String, value: String) -> some View {
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

    private func transcriptCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Transcript").font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcript: \(text)")
    }

    private func formatDuration(_ s: Int) -> String {
        s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60 == 0 ? "" : "\(s % 60)s")".trimmingCharacters(in: .whitespaces)
    }

    private func relativeTimestamp(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) ?? {
            let alt = ISO8601DateFormatter(); alt.formatOptions = [.withInternetDateTime]
            return alt.date(from: iso)
        }() else { return iso }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - VoicemailDetailPanel

private struct VoicemailDetailPanel: View {
    let entry: VoicemailEntry
    let onMarkHeard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                // Header
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "voicemail")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(entry.customerName ?? entry.phoneNumber)
                            .font(.title2)
                            .fontWeight(.semibold)
                        if entry.customerName != nil {
                            Text(entry.phoneNumber)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, DesignTokens.Spacing.lg)

                // Inline player
                VoicemailInlinePlayer(entry: entry)

                // Meta + actions
                VStack(spacing: DesignTokens.Spacing.md) {
                    if !entry.heard {
                        Button {
                            onMarkHeard()
                        } label: {
                            Label("Mark as Heard", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.brandGlass)
                        .accessibilityLabel("Mark voicemail as heard")
                    }

                    Button {
                        CallQuickAction.placeCall(to: entry.phoneNumber)
                    } label: {
                        Label("Call back", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.brandGlass)
                    .keyboardShortcut(VoiceShortcut.callback, modifiers: VoiceShortcut.commandModifiers)
                    .accessibilityLabel("Call back \(entry.customerName ?? entry.phoneNumber)")
                }

                // Transcript
                if let text = entry.transcriptText, !text.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("Transcript").font(.headline)
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(DesignTokens.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Transcript: \(text)")
                }

                Spacer(minLength: DesignTokens.Spacing.huge)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxxl)
        }
        .navigationTitle(entry.customerName ?? entry.phoneNumber)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
#endif
