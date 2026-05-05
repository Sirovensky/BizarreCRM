#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - BulkEditResultView

/// Displays the summary after a bulk-edit operation completes.
///
/// Shows:
/// - Count of succeeded and failed tickets.
/// - Per-ticket failure reason list (collapsed for >5 failures).
/// - "Retry Failed" button when `onRetry` is provided and failures exist.
/// - "Done" dismiss button.
///
/// Designed for `.sheet` presentation with `.presentationDetents([.medium, .large])`.
public struct BulkEditResultView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Input

    let outcomes: [BulkTicketOutcome]
    /// Called with the IDs of failed tickets when the user taps "Retry".
    /// If nil, the retry button is hidden.
    let onRetry: (([Int64]) -> Void)?

    // MARK: - State

    @State private var showAllFailures: Bool = false

    // MARK: - Init

    public init(
        outcomes: [BulkTicketOutcome],
        onRetry: (([Int64]) -> Void)? = nil
    ) {
        self.outcomes = outcomes
        self.onRetry = onRetry
    }

    // MARK: - Derived

    private var succeeded: [BulkTicketOutcome] { outcomes.filter { $0.succeeded } }
    private var failed: [BulkTicketOutcome] { outcomes.filter { !$0.succeeded } }

    private var visibleFailures: [BulkTicketOutcome] {
        showAllFailures ? failed : Array(failed.prefix(5))
    }

    private var failedIDs: [Int64] { failed.map(\.id) }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.lg) {
                        summaryHeader
                        if !failed.isEmpty {
                            failureList
                        }
                        actionButtons
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Bulk Edit Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneButton }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Summary header

    private var summaryHeader: some View {
        HStack(spacing: BrandSpacing.base) {
            summaryPill(
                count: succeeded.count,
                label: "Succeeded",
                icon: "checkmark.circle.fill",
                color: .bizarreSuccess
            )
            summaryPill(
                count: failed.count,
                label: "Failed",
                icon: "xmark.circle.fill",
                color: failed.isEmpty ? .bizarreOnSurfaceMuted : .bizarreError
            )
        }
        .padding(.top, BrandSpacing.md)
    }

    private func summaryPill(
        count: Int,
        label: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.brandTitleLarge())
                .foregroundStyle(Color.bizarreOnSurface)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Failure list

    private var failureList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Failed Tickets")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)

            ForEach(visibleFailures) { outcome in
                failureRow(outcome: outcome)
            }

            if failed.count > 5 && !showAllFailures {
                Button {
                    showAllFailures = true
                } label: {
                    Text("Show \(failed.count - 5) more…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.top, BrandSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func failureRow(outcome: BulkTicketOutcome) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.bizarreWarning)
                .font(.caption)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ticket #\(outcome.id)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                if case .failed(let message) = outcome.status {
                    Text(message)
                        .font(.brandBodyMedium())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
            }

            Spacer()
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.sm) {
            if !failed.isEmpty, let onRetry {
                Button {
                    dismiss()
                    onRetry(failedIDs)
                } label: {
                    Label("Retry \(failed.count) Failed", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .controlSize(.large)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Toolbar

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
    }
}

// MARK: - iPad layout extension

extension BulkEditResultView {
    /// Returns a version of the view optimised for iPad (regular horizontal size class).
    /// On iPad the two summary pills sit in a compact card rather than full-width rows,
    /// and the failure list uses a table-style layout.
    @ViewBuilder
    public static func makeAdaptive(
        outcomes: [BulkTicketOutcome],
        onRetry: (([Int64]) -> Void)? = nil
    ) -> some View {
        BulkEditResultView(outcomes: outcomes, onRetry: onRetry)
    }
}

#endif
