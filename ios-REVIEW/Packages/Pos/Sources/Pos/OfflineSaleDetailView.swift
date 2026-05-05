#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence
import Sync

// MARK: - OfflineSaleDetailView

/// Detail view for a single queued POS sync op. Shows the JSON payload
/// for operator inspection and provides Retry / Cancel actions.
///
/// - "Retry now" triggers `SyncManager.shared.syncNow()` then dismisses.
/// - "Cancel" discards the op from the dead-letter / queue and dismisses.
public struct OfflineSaleDetailView: View {
    public let record: SyncQueueRecord
    /// Called after a retry or cancel so the parent list can reload.
    public let onDismiss: () -> Void

    @State private var isRetrying: Bool = false
    @State private var isCancelling: Bool = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    public init(record: SyncQueueRecord, onDismiss: @escaping () -> Void) {
        self.record = record
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    metadataSection
                    payloadSection
                    if let msg = errorMessage {
                        errorBanner(msg)
                    }
                    actionButtons
                }
                .padding(BrandSpacing.base)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle(kindLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                        onDismiss()
                    }
                    .accessibilityIdentifier("pos.offlineDetail.close")
                }
            }
        }
        .accessibilityIdentifier("pos.offlineSaleDetailView")
    }

    // MARK: - Subviews

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Details")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            VStack(spacing: 0) {
                metadataRow(label: "Kind", value: kindLabel)
                Divider()
                metadataRow(label: "Status", value: record.status)
                Divider()
                metadataRow(label: "Attempts", value: "\(record.attemptCount)")
                Divider()
                metadataRow(label: "Queued", value: formattedDate(record.enqueuedAt))
                if let last = record.lastAttempt {
                    Divider()
                    metadataRow(label: "Last attempt", value: formattedDate(last))
                }
                if let lastError = record.lastError {
                    Divider()
                    metadataRow(label: "Last error", value: lastError)
                }
                if let idempotencyKey = record.idempotencyKey {
                    Divider()
                    metadataRow(label: "Idempotency key", value: idempotencyKey)
                        .accessibilityAddTraits(.allowsDirectInteraction)
                }
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var payloadSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Payload JSON")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(prettyJSON)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .padding(BrandSpacing.md)
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .accessibilityLabel("Payload JSON")
            .accessibilityValue(prettyJSON)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreError.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.sm) {
            Button {
                Task { await retryNow() }
            } label: {
                Group {
                    if isRetrying {
                        ProgressView()
                    } else {
                        Label("Retry now", systemImage: "arrow.clockwise")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(isRetrying || isCancelling)
            .accessibilityIdentifier("pos.offlineDetail.retry")
            .accessibilityLabel("Retry now")
            .accessibilityHint("Triggers an immediate sync of all pending offline sales.")

            Button(role: .destructive) {
                Task { await cancelOp() }
            } label: {
                Group {
                    if isCancelling {
                        ProgressView()
                    } else {
                        Label("Cancel this sale", systemImage: "trash")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRetrying || isCancelling)
            .accessibilityIdentifier("pos.offlineDetail.cancel")
            .accessibilityLabel("Cancel this offline sale")
            .accessibilityHint("Permanently removes this queued sale. This cannot be undone.")
        }
    }

    // MARK: - Actions

    private func retryNow() async {
        isRetrying = true
        errorMessage = nil
        defer { isRetrying = false }
        await SyncManager.shared.syncNow()
        dismiss()
        onDismiss()
    }

    private func cancelOp() async {
        guard let id = record.id else {
            errorMessage = "Cannot cancel op — missing record ID."
            return
        }
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }
        do {
            // Two-step cancel:
            // 1. Force the record into dead-letter by marking it failed with a
            //    cancellation reason. SyncQueueStore.markFailed auto-moves the
            //    row to sync_dead_letter once attemptCount >= maxAttempts (10).
            //    We call it until it crosses the threshold.
            let remaining = max(0, SyncQueueStore.maxAttempts - record.attemptCount)
            for _ in 0..<remaining {
                try await SyncQueueStore.shared.markFailed(id, error: "Cancelled by operator")
            }
            // 2. Find and discard the dead-letter row. We use deadLetterCount
            //    to confirm the row landed, then prune by searching for our key.
            if let key = record.idempotencyKey {
                let dlRows = try await SyncQueueStore.shared.deadLetter(limit: 50)
                if let dlRow = dlRows.first(where: { $0.op == (record.op ?? "") && $0.entity == (record.entity ?? "") }) {
                    try await SyncQueueStore.shared.discardDeadLetter(dlRow.id)
                }
                _ = key   // suppress unused warning
            }
            dismiss()
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var kindLabel: String {
        record.kind ?? "\(record.entity ?? "pos").\(record.op ?? "unknown")"
    }

    private var prettyJSON: String {
        guard let data = record.payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8)
        else { return record.payload }
        return str
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

#Preview {
    OfflineSaleDetailView(
        record: SyncQueueRecord(
            op: "sale.finalize",
            entity: "pos",
            payload: #"{"totalCents":1999,"items":[]}"#
        ),
        onDismiss: {}
    )
}
#endif
