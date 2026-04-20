import SwiftUI
import Observation
import Core
import DesignSystem
import Persistence

/// §20.2 — Settings → Sync diagnostics. Surfaces pending + dead-letter
/// rows so the operator can triage out-of-band (retry a specific row,
/// discard the ones they don't care about).
///
/// Read-only except for the Retry / Discard per-row actions. All queue
/// mutations route through `SyncQueueStore` to keep the replay logic in
/// one place.
public struct SyncDiagnosticsView: View {
    @State private var vm = SyncDiagnosticsViewModel()

    public init() {}

    public var body: some View {
        List {
            Section("Queue") {
                LabeledContent("Pending") {
                    Text("\(vm.pendingCount)")
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOnSurface)
                }
                LabeledContent("Dead-letter") {
                    Text("\(vm.deadLetterRows.count)")
                        .monospacedDigit()
                        .foregroundStyle(vm.deadLetterRows.isEmpty ? .bizarreOnSurfaceMuted : .bizarreWarning)
                }
            }

            if !vm.deadLetterRows.isEmpty {
                Section {
                    ForEach(vm.deadLetterRows) { row in
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            HStack(spacing: BrandSpacing.xs) {
                                Text("\(row.entity).\(row.op)")
                                    .font(.brandTitleSmall())
                                    .foregroundStyle(.bizarreOnSurface)
                                Spacer()
                                Text(Self.relative(from: row.movedAt))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            if let err = row.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreError)
                                    .lineLimit(2)
                            }
                            HStack {
                                Button("Retry") { Task { await vm.retry(id: row.id) } }
                                    .buttonStyle(.bordered)
                                    .tint(.bizarreTeal)
                                Button("Discard", role: .destructive) {
                                    Task { await vm.discard(id: row.id) }
                                }
                                .buttonStyle(.bordered)
                                .tint(.bizarreError)
                            }
                            .accessibilityElement(children: .contain)
                        }
                        .padding(.vertical, BrandSpacing.xxs)
                    }
                } header: {
                    Text("Failed syncs")
                } footer: {
                    Text("Retry re-queues with a fresh idempotency key. Discard removes the row permanently.")
                        .font(.brandLabelSmall())
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.bizarreSuccess)
                            .accessibilityHidden(true)
                        Text("No failed syncs.")
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Sync diagnostics")
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    /// Short relative timestamp — "3m ago", "1h ago". Avoids a full
    /// DateComponentsFormatter round trip since the DLQ should be small.
    private static func relative(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:         return "just now"
        case ..<3600:       return "\(seconds / 60)m ago"
        case ..<86400:      return "\(seconds / 3600)h ago"
        default:            return "\(seconds / 86400)d ago"
        }
    }
}

@MainActor
@Observable
final class SyncDiagnosticsViewModel {
    var pendingCount: Int = 0
    var deadLetterRows: [SyncQueueStore.DeadLetterRow] = []

    func load() async {
        pendingCount = (try? await SyncQueueStore.shared.pendingCount()) ?? 0
        deadLetterRows = (try? await SyncQueueStore.shared.deadLetter(limit: 50)) ?? []
    }

    func retry(id: Int64) async {
        try? await SyncQueueStore.shared.retryDeadLetter(id)
        await load()
    }

    func discard(id: Int64) async {
        try? await SyncQueueStore.shared.discardDeadLetter(id)
        await load()
    }
}
