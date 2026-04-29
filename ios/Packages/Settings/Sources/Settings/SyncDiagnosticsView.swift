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

            // MARK: §19.23 — Disk usage breakdown
            Section("Disk usage") {
                LabeledContent("GRDB database") {
                    Text(vm.dbSizeLabel)
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOnSurface)
                }
                .accessibilityLabel("GRDB database size: \(vm.dbSizeLabel)")
                .accessibilityIdentifier("data.diskUsage.grdb")

                LabeledContent("Image cache") {
                    Text(vm.imageCacheSizeLabel)
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOnSurface)
                }
                .accessibilityLabel("Image cache size: \(vm.imageCacheSizeLabel)")
                .accessibilityIdentifier("data.diskUsage.images")

                LabeledContent("Log files") {
                    Text(vm.logsSizeLabel)
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOnSurface)
                }
                .accessibilityLabel("Log files size: \(vm.logsSizeLabel)")
                .accessibilityIdentifier("data.diskUsage.logs")

                LabeledContent("Total app data") {
                    Text(vm.totalSizeLabel)
                        .monospacedDigit()
                        .font(.brandBodyMedium().bold())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .accessibilityLabel("Total app data: \(vm.totalSizeLabel)")
                .accessibilityIdentifier("data.diskUsage.total")
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
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
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

    // §19.23 disk usage breakdown
    var dbSizeLabel: String = "—"
    var imageCacheSizeLabel: String = "—"
    var logsSizeLabel: String = "—"
    var totalSizeLabel: String = "—"

    func load() async {
        pendingCount = (try? await SyncQueueStore.shared.pendingCount()) ?? 0
        deadLetterRows = (try? await SyncQueueStore.shared.deadLetter(limit: 50)) ?? []
        refreshDiskUsage()
    }

    func retry(id: Int64) async {
        try? await SyncQueueStore.shared.retryDeadLetter(id)
        await load()
    }

    func discard(id: Int64) async {
        try? await SyncQueueStore.shared.discardDeadLetter(id)
        await load()
    }

    // MARK: - §19.23 Disk usage

    private func refreshDiskUsage() {
        let fm = FileManager.default
        let docs = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? URL(fileURLWithPath: NSHomeDirectory())
        let caches = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? URL(fileURLWithPath: NSHomeDirectory())
        let library = docs.deletingLastPathComponent().appendingPathComponent("Library")

        let dbSize    = directorySize(at: docs, matching: { $0.hasSuffix(".sqlite") || $0.hasSuffix(".db") || $0.hasSuffix(".sqlite-wal") || $0.hasSuffix(".sqlite-shm") })
        let imageSize = directorySize(at: caches, matching: { _ in true })
        let logsSize  = directorySize(at: library.appendingPathComponent("Logs"), matching: { _ in true })
        let total     = dbSize + imageSize + logsSize

        dbSizeLabel         = Self.format(bytes: dbSize)
        imageCacheSizeLabel = Self.format(bytes: imageSize)
        logsSizeLabel       = Self.format(bytes: logsSize)
        totalSizeLabel      = Self.format(bytes: total)
    }

    /// Recursively sums file sizes under `url`, optionally filtered by file-name predicate.
    private func directorySize(at url: URL, matching predicate: (String) -> Bool = { _ in true }) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                guard predicate(fileURL.lastPathComponent) else { continue }
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                total += Int64(size)
            }
        }
        return total
    }

    private static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
