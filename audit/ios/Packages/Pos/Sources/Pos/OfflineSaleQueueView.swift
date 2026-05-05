#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence
import Sync

// MARK: - OfflineSaleQueueView

/// Sheet listing all pending POS offline sales. Each row shows the op kind,
/// entity, relative enqueue time, and attempt count. Tapping a row navigates
/// to `OfflineSaleDetailView` for payload inspection and retry/cancel.
public struct OfflineSaleQueueView: View {
    @State private var vm = OfflineSaleQueueViewModel()
    @State private var selected: SyncQueueRecord? = nil
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.ops.isEmpty {
                    ProgressView("Loading queued sales…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.ops.isEmpty {
                    emptyState
                } else {
                    queueList
                }
            }
            .navigationTitle("Offline Sales Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("pos.offlineQueue.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await vm.retryAll() }
                    } label: {
                        Label("Sync now", systemImage: "arrow.clockwise")
                    }
                    .disabled(vm.ops.isEmpty)
                    .accessibilityIdentifier("pos.offlineQueue.syncNow")
                }
            }
            .sheet(item: $selected) { record in
                OfflineSaleDetailView(record: record) {
                    selected = nil
                    Task { await vm.load() }
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
        .accessibilityIdentifier("pos.offlineQueueView")
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            VStack(spacing: BrandSpacing.xs) {
                Text("Queue is empty")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("All sales have been synced to the server.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queueList: some View {
        List(vm.ops) { record in
            Button {
                selected = record
            } label: {
                OfflineSaleQueueRow(record: record)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pos.offlineQueue.row.\(record.idempotencyKey ?? "?")")
            .listRowBackground(Color.bizarreSurface1)
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - OfflineSaleQueueRow

private struct OfflineSaleQueueRow: View {
    let record: SyncQueueRecord

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            // Kind badge
            Text(kindLabel)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnOrange)
                .padding(.horizontal, BrandSpacing.xs)
                .padding(.vertical, 2)
                .background(Color.bizarreOrange, in: Capsule())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(kindLabel)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)

                if record.attemptCount > 0 {
                    Text("\(record.attemptCount) attempt\(record.attemptCount == 1 ? "" : "s")")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreWarning)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(relativeTime)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view details and retry or cancel.")
    }

    private var kindLabel: String {
        record.kind ?? "\(record.entity ?? "pos").\(record.op ?? "unknown")"
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: record.enqueuedAt, relativeTo: Date())
    }

    private var accessibilityLabel: String {
        "\(kindLabel), enqueued \(relativeTime)"
        + (record.attemptCount > 0 ? ", \(record.attemptCount) failed attempt\(record.attemptCount == 1 ? "" : "s")" : "")
    }
}

// MARK: - SyncQueueRecord + Identifiable for sheet(item:)

extension SyncQueueRecord: @retroactive Identifiable {}

#Preview {
    OfflineSaleQueueView()
}
#endif
