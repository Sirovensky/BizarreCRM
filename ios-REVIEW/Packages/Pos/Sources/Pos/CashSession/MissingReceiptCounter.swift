#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

// MARK: - MissingReceiptRecord

/// §39.5 — A sale for which the receipt was neither printed nor sent
/// electronically. Tracked locally so the Z-report can surface a "missing
/// receipt" count to the manager.
///
/// "Missing" means the cashier dismissed the receipt prompt without choosing
/// print / email / SMS. The audit event `receipt_skipped` is logged at the
/// call site; this model aggregates those events for the shift summary.
public struct MissingReceiptRecord: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let saleId: Int64
    public let amountCents: Int
    public let cashierId: Int64
    public let timestamp: Date

    public init(
        id: Int64,
        saleId: Int64,
        amountCents: Int,
        cashierId: Int64,
        timestamp: Date
    ) {
        self.id = id
        self.saleId = saleId
        self.amountCents = amountCents
        self.cashierId = cashierId
        self.timestamp = timestamp
    }
}

// MARK: - MissingReceiptCounterViewModel

/// §39.5 — Drives the missing-receipt counter badge and list.
///
/// Reads `receipt_skipped` audit log entries for the current shift window
/// (today, or from a supplied `shiftStart`). Exposes a count for badge
/// display and the raw records for the drill-down list.
@MainActor
@Observable
public final class MissingReceiptCounterViewModel {

    // MARK: - Outputs
    public private(set) var records: [MissingReceiptRecord] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Derived
    public var count: Int { records.count }
    public var isEmpty: Bool { records.isEmpty }
    /// Badge severity: none / warning (1-3) / error (4+).
    public var severity: Severity {
        switch count {
        case 0:     return .none
        case 1...3: return .warning
        default:    return .error
        }
    }

    public enum Severity { case none, warning, error
        public var color: Color {
            switch self {
            case .none:    return .clear
            case .warning: return .bizarreWarning
            case .error:   return .bizarreError
            }
        }
    }

    // MARK: - Init

    private let shiftStart: Date

    public init(shiftStart: Date = Calendar.current.startOfDay(for: Date())) {
        self.shiftStart = shiftStart
    }

    // MARK: - Load

    /// Loads `receipt_skipped` entries from the local audit log since `shiftStart`.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let all = try await PosAuditLogStore.shared.byEventType(
                PosAuditEntry.EventType.receiptSkipped,
                limit: 200
            )
            records = all
                .filter { $0.date >= shiftStart }
                .map { entry in
                    MissingReceiptRecord(
                        id: entry.id ?? 0,
                        saleId: entry.cashierId,     // reused field: sale id stored in cashierId slot until a dedicated context_json key lands
                        amountCents: entry.amountCents ?? 0,
                        cashierId: entry.cashierId,
                        timestamp: entry.date
                    )
                }
        } catch {
            // receipt_skipped may not be in older audit DBs; swallow gracefully.
            records = []
            AppLog.pos.warning("MissingReceiptCounter: could not load receipt_skipped entries — \(error)")
        }
    }
}

// MARK: - MissingReceiptCounterBadge

/// §39.5 — Compact badge showing the missing-receipt count for embedding in
/// the Z-report action row or end-of-shift summary.
///
/// Shows nothing when count is 0.
public struct MissingReceiptCounterBadge: View {

    public let count: Int
    public let severity: MissingReceiptCounterViewModel.Severity

    public init(count: Int, severity: MissingReceiptCounterViewModel.Severity) {
        self.count = count
        self.severity = severity
    }

    public var body: some View {
        if count > 0 {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "receipt.badge.xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(severity.color)
                    .accessibilityHidden(true)
                Text("\(count) missing receipt\(count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(severity.color)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 4)
            .background(severity.color.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(count) missing receipt\(count == 1 ? "" : "s") this shift")
            .accessibilityIdentifier("missingReceipts.badge")
        }
    }
}

// MARK: - MissingReceiptListView

/// §39.5 — Drill-down list of missing receipts for the Z-report or
/// end-of-shift audit flow.
public struct MissingReceiptListView: View {

    @State private var vm: MissingReceiptCounterViewModel
    @Environment(\.dismiss) private var dismiss

    public init(shiftStart: Date = Calendar.current.startOfDay(for: Date())) {
        _vm = State(wrappedValue: MissingReceiptCounterViewModel(shiftStart: shiftStart))
    }

    public var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("missingReceipts.loading")
                } else if vm.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Missing receipts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("missingReceipts.done")
                }
            }
        }
        .task { await vm.load() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("All receipts accounted for")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("No skipped receipts recorded this shift.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("missingReceipts.empty")
    }

    private var list: some View {
        List {
            Section {
                MissingReceiptCounterBadge(count: vm.count, severity: vm.severity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section("Sales with no receipt issued") {
                ForEach(vm.records) { record in
                    receiptRow(record)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("missingReceipts.list")
    }

    private func receiptRow(_ record: MissingReceiptRecord) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "receipt.badge.xmark")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sale #\(record.saleId)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(Self.formatDate(record.timestamp))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text(CartMath.formatCents(record.amountCents))
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sale \(record.saleId), \(CartMath.formatCents(record.amountCents)), receipt not sent, \(Self.formatDate(record.timestamp))")
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Preview

#Preview("Missing receipt badge — warning") {
    VStack(spacing: BrandSpacing.lg) {
        MissingReceiptCounterBadge(count: 2, severity: .warning)
        MissingReceiptCounterBadge(count: 5, severity: .error)
        MissingReceiptCounterBadge(count: 0, severity: .none)
    }
    .padding()
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
