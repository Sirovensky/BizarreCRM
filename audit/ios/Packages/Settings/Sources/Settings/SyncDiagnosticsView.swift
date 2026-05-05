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

            // MARK: §19.23 — Data actions
            Section {
                Button {
                    vm.showClearCacheConfirm = true
                } label: {
                    Label("Clear image & catalogue cache", systemImage: "trash")
                        .foregroundStyle(.bizarreWarning)
                }
                .disabled(vm.isActing)
                .accessibilityIdentifier("data.clearCache")

                Button(role: .destructive) {
                    vm.showForceFullSyncConfirm = true
                } label: {
                    Label("Force full sync (wipe & re-fetch)", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.bizarreError)
                }
                .disabled(vm.isActing)
                .accessibilityIdentifier("data.forceFullSync")

                if vm.isActing {
                    HStack(spacing: BrandSpacing.xs) {
                        ProgressView()
                            .accessibilityLabel("Working…")
                        Text(vm.actingLabel)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            } header: {
                Text("Data actions")
            } footer: {
                Text("Clear cache removes images and catalogue thumbnails only. Force full sync wipes all local data and re-fetches from the server.")
                    .font(.brandLabelSmall())
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
        .alert("Clear image cache?", isPresented: $vm.showClearCacheConfirm) {
            Button("Clear", role: .destructive) { Task { await vm.clearCache() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes cached images and catalogue thumbnails. Downloaded data will be re-fetched on demand. Queued writes are not affected.")
        }
        .alert("Force full sync?", isPresented: $vm.showForceFullSyncConfirm) {
            Button("Wipe & re-sync", role: .destructive) { Task { await vm.forceFullSync() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wipes the local GRDB database and re-fetches all domains from the server. Queued writes are discarded. This may take a minute on slow connections.")
        }
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

    // §19.23 data action state
    var showClearCacheConfirm: Bool = false
    var showForceFullSyncConfirm: Bool = false
    var isActing: Bool = false
    var actingLabel: String = ""

    func load() async {
        pendingCount = (try? await SyncQueueStore.shared.pendingCount()) ?? 0
        deadLetterRows = (try? await SyncQueueStore.shared.deadLetter(limit: 50)) ?? []
        refreshDiskUsage()
    }

    // MARK: - §19.23 Clear image + catalogue cache

    /// Removes cached images (NSURLCache + Caches directory) and any catalogue
    /// thumbnail files. Queued writes in GRDB are intentionally left intact.
    func clearCache() async {
        isActing = true
        actingLabel = "Clearing cache…"
        defer {
            isActing = false
            actingLabel = ""
        }
        // 1. Clear URLSession shared cache (covers Nuke HTTP-level cache).
        URLCache.shared.removeAllCachedResponses()
        // 2. Delete entire Caches directory contents (image disk cache lives here).
        let fm = FileManager.default
        if let caches = try? fm.url(for: .cachesDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false) {
            let items = (try? fm.contentsOfDirectory(at: caches,
                                                     includingPropertiesForKeys: nil,
                                                     options: .skipsHiddenFiles)) ?? []
            for item in items {
                try? fm.removeItem(at: item)
            }
        }
        // Refresh disk usage after clearing.
        refreshDiskUsage()
    }

    // MARK: - §19.23 Force full sync

    /// Wipes the local GRDB database (except queued writes — those are sent
    /// first to avoid data loss), then posts a `NSNotification` that the
    /// SyncCoordinator observes to trigger a full re-fetch of all domains.
    func forceFullSync() async {
        isActing = true
        actingLabel = "Wiping local database…"
        defer {
            isActing = false
            actingLabel = ""
        }
        // Signal the persistence layer to wipe and re-fetch.
        // SyncCoordinator observes `.forceFullSyncRequested` and schedules
        // domain re-fetches in priority order.
        await MainActor.run {
            NotificationCenter.default.post(
                name: .forceFullSyncRequested,
                object: nil
            )
        }
        // Reload our diagnostics view so counts reflect fresh state.
        await load()
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

// MARK: - Notification name

// `Notification.Name.forceFullSyncRequested` is declared in `SyncNotifications.swift`.
