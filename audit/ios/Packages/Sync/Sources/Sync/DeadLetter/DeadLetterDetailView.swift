import SwiftUI
import DesignSystem
import Core

// MARK: - DeadLetterDetailView

/// Shows full JSON payload + error for a dead-letter op.
/// Retry re-enqueues with fresh attempt budget. Discard permanently removes.
public struct DeadLetterDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let item: DeadLetterItem

    /// Shared VM so the list updates after retry/discard.
    let viewModel: DeadLetterViewModel

    @State private var isRetrying: Bool = false
    @State private var isDiscarding: Bool = false
    @State private var showDiscard: Bool = false
    @State private var detailItem: DeadLetterItem?
    @State private var loadingDetail: Bool = true

    public init(item: DeadLetterItem, viewModel: DeadLetterViewModel) {
        self.item = item
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                headerSection
                errorSection
                payloadSection
                actionButtons
            }
            .padding(BrandSpacing.base)
        }
        .navigationTitle("Dead Letter Detail")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .accessibilityLabel("Close detail view")
            }
        }
        .task {
            await loadDetail()
        }
        .alert("Discard Operation?", isPresented: $showDiscard) {
            Button("Discard", role: .destructive) {
                Task { await performDiscard() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the failed operation. It cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("\(item.entity) — \(item.op.uppercased())")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }

            Text("Failed after \(item.attemptCount) attempt\(item.attemptCount == 1 ? "" : "s")")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Text("Moved to dead letter: \(item.movedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let error = item.lastError {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Error Reason")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(error)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .textSelection(.enabled)
                    .accessibilityLabel("Error: \(error)")
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
    }

    // MARK: - Payload

    private var payloadSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Payload (JSON)")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            if loadingDetail {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Loading payload")
            } else {
                let payload = detailItem?.payload ?? item.payload
                if payload.isEmpty {
                    Text("No payload")
                        .font(.brandMono())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } else {
                    Text(prettyPrint(payload))
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                        .accessibilityLabel("JSON payload")
                }
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface2.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.sm) {
            Button {
                Task { await performRetry() }
            } label: {
                HStack {
                    if isRetrying {
                        ProgressView()
                            .tint(.bizarreOnOrange)
                    }
                    Text(isRetrying ? "Retrying…" : "Retry")
                        .font(.brandTitleSmall())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(isRetrying || isDiscarding)
            .accessibilityLabel("Retry this sync operation")
            .accessibilityHint("Re-enqueues the operation for another attempt")

            Button(role: .destructive) {
                showDiscard = true
            } label: {
                Text("Discard")
                    .font(.brandTitleSmall())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandGlass)
            .tint(.bizarreError)
            .disabled(isRetrying || isDiscarding)
            .accessibilityLabel("Discard this operation")
            .accessibilityHint("Permanently removes the failed operation")
        }
    }

    // MARK: - Actions implementation

    private func loadDetail() async {
        loadingDetail = true
        do {
            detailItem = try await DeadLetterRepository.shared.fetchDetail(item.id)
        } catch {
            AppLog.sync.error("DeadLetterDetailView.loadDetail failed: \(String(describing: error), privacy: .public)")
        }
        loadingDetail = false
    }

    private func performRetry() async {
        isRetrying = true
        await viewModel.retry(id: item.id)
        isRetrying = false
        dismiss()
    }

    private func performDiscard() async {
        isDiscarding = true
        await viewModel.discard(id: item.id)
        isDiscarding = false
        dismiss()
    }

    // MARK: - Helpers

    private func prettyPrint(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return result
    }
}
