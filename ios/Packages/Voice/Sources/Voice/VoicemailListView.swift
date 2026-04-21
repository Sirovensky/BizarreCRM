#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

/// §42.5 — Voicemail list screen.
///
/// Server endpoint is DEFERRED (no `voicemail.routes.ts` exists). This view
/// renders a "Coming soon" banner when the API returns 404. When the endpoint
/// ships, the view will automatically start populating.
public struct VoicemailListView: View {

    @State private var viewModel: VoicemailViewModel
    @State private var playerEntry: VoicemailEntry?

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        self._viewModel = State(initialValue: VoicemailViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            contentBody
                .navigationTitle("Voicemail")
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh voicemails")
                    }
                }
        }
        .sheet(item: $playerEntry) { entry in
            VoicemailPlayerView(entry: entry) {
                // On dismiss, mark as heard
                Task { await viewModel.markHeard(entry: entry) }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentBody: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading voicemails…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading voicemails")

        case .loaded(let items):
            if items.isEmpty {
                emptyState
            } else {
                voicemailList(items)
            }

        case .failed(let message):
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

        case .comingSoon:
            comingSoonView
        }
    }

    // MARK: - List

    private func voicemailList(_ items: [VoicemailEntry]) -> some View {
        List(items) { entry in
            VoicemailRow(entry: entry) {
                playerEntry = entry
            }
            .swipeActions(edge: .trailing) {
                Button {
                    Task { await viewModel.markHeard(entry: entry) }
                } label: {
                    Label("Mark heard", systemImage: "checkmark.circle")
                }
                .tint(.blue)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty / coming-soon

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "voicemail")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No voicemails")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No voicemails")
    }

    private var comingSoonView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "voicemail.badge.clock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Coming soon")
                .font(.title3)
            Text("Voicemail is not yet available on this server.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voicemail coming soon")
    }
}

// MARK: - VoicemailRow

private struct VoicemailRow: View {
    let entry: VoicemailEntry
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(entry.heard ? .secondary : .blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play voicemail from \(entry.customerName ?? entry.phoneNumber)")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack {
                    Text(entry.customerName ?? entry.phoneNumber)
                        .font(.body)
                        .fontWeight(entry.heard ? .regular : .semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !entry.heard {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Unheard")
                    }
                }
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if let ts = entry.receivedAt {
                        Text(relativeTimestamp(ts))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let dur = entry.durationSeconds {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatDuration(dur))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func formatDuration(_ s: Int) -> String {
        s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60 == 0 ? "" : "\(s % 60)s")".trimmingCharacters(in: .whitespaces)
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
        let heard = entry.heard ? ", heard" : ", unheard"
        let dur = entry.durationSeconds.map { ", \(formatDuration($0))" } ?? ""
        return "Voicemail from \(who)\(dur)\(heard)"
    }
}

// MARK: - VoicemailViewModel

@MainActor
@Observable
final class VoicemailViewModel {

    enum State {
        case loading
        case loaded([VoicemailEntry])
        case failed(String)
        case comingSoon
    }

    private(set) var state: State = .loading
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func load() async {
        state = .loading
        do {
            let items = try await api.listVoicemails()
            state = .loaded(items)
        } catch let error as APITransportError {
            if case .httpStatus(404, _) = error {
                state = .comingSoon
            } else {
                state = .failed(error.errorDescription ?? "Could not load voicemails.")
            }
        } catch {
            state = .failed("Could not load voicemails. Please try again.")
        }
    }

    func markHeard(entry: VoicemailEntry) async {
        // Best-effort — swallow errors since this is a housekeeping action.
        try? await api.markVoicemailHeard(id: entry.id)
        // Optimistically update local state
        if case .loaded(let items) = state {
            let updated = items.map { item -> VoicemailEntry in
                guard item.id == entry.id else { return item }
                return VoicemailEntry(
                    id: item.id,
                    phoneNumber: item.phoneNumber,
                    customerName: item.customerName,
                    receivedAt: item.receivedAt,
                    durationSeconds: item.durationSeconds,
                    audioUrl: item.audioUrl,
                    transcriptText: item.transcriptText,
                    heard: true
                )
            }
            state = .loaded(updated)
        }
    }
}
#endif
