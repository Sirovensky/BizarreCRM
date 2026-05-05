import Foundation
import Persistence

#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §39 — Z-Report history list.
///
/// Shows all recent sessions (newest first) from the local
/// `CashRegisterStore`. Each row taps into a `ZReportView` for the full
/// shift summary.
///
/// The server does not yet expose a `/pos/cash-sessions` history endpoint
/// (ticket POS-SESSIONS-001), so this view is driven entirely by the local
/// GRDB store. When server sync lands, rows with `serverId != nil` can be
/// fetched via the Networking layer.
public struct ZReportDetailView: View {

    // MARK: - State

    @State private var sessions: [CashSessionRecord] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedSession: CashSessionRecord?

    @Environment(\.dismiss) private var dismiss

    private let repository: CashSessionRepository

    // MARK: - Init

    public init(repository: CashSessionRepository) {
        self.repository = repository
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading shift history…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("zReportHistory.loading")
                } else if sessions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Shift history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("zReportHistory.done")
                }
            }
            .alert("Load error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task { await load() }
        .sheet(item: $selectedSession) { session in
            ZReportView(session: session)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No shift history")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("Closed sessions will appear here.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("zReportHistory.empty")
    }

    private var list: some View {
        List {
            ForEach(sessions) { session in
                Button {
                    selectedSession = session
                } label: {
                    sessionRow(session)
                }
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityIdentifier("zReportHistory.row.\(session.id ?? 0)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("zReportHistory.list")
    }

    private func sessionRow(_ session: CashSessionRecord) -> some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(Self.formatDate(session.openedAt))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(session.isOpen ? "Open" : closedLabel(session))
                    .font(.brandLabelSmall())
                    .foregroundStyle(session.isOpen ? .bizarreSuccess : .bizarreOnSurfaceMuted)
            }
            Spacer(minLength: BrandSpacing.sm)
            if let variance = session.varianceCents {
                let band = CashVariance.band(cents: variance)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CloseRegisterSheet.formatSigned(cents: variance))
                        .font(.brandTitleMedium())
                        .foregroundStyle(band.color)
                        .monospacedDigit()
                    Text(band.shortLabel)
                        .font(.brandLabelSmall())
                        .foregroundStyle(band.color)
                }
            }
            Image(systemName: "chevron.right")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Data

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await repository.recentSessions(limit: 50)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Formatting helpers

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func closedLabel(_ session: CashSessionRecord) -> String {
        guard let closedAt = session.closedAt else { return "Closed" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return "Closed \(f.string(from: closedAt))"
    }
}

#endif // canImport(UIKit)
