#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

/// §16.11 — Loss-prevention audit log viewer.
///
/// Displays the last 50 POS audit events grouped by calendar day.
/// Reachable from POS overflow ⋯ → Register → "View audit log".
///
/// Layout: simple `List` (NOT glass — audit rows are content, not chrome).
/// Each row: event-type badge + amount + cashier/manager ids + relative time.
///
/// iPad: the sheet renders at `.large` so the list is usable without scrolling.
public struct PosAuditLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PosAuditEntry] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String? = nil

    public init() {}

    public var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading audit log…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                errorView(err)
            } else if entries.isEmpty {
                emptyView
            } else {
                auditList
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Audit log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("pos.auditLog.done")
            }
        }
        .task { await loadEntries() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sub-views

    private var auditList: some View {
        List {
            // §16 — manager override summary row: surfaces today's count so a
            // loss-prevention manager sees unusual overrides at a glance.
            let todayOverrides = managerOverrideCountToday
            if todayOverrides > 0 {
                Section {
                    managerOverrideSummaryRow(count: todayOverrides)
                        .listRowBackground(Color.bizarreWarning.opacity(0.08))
                } header: {
                    Text("Today's manager overrides")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            // §39 — no-sale summary row: a dedicated header section that
            // surfaces today's no-sale count at a glance for loss prevention,
            // even before the manager scrolls into the chronological log.
            let todayNoSales = noSaleCountToday
            if todayNoSales > 0 {
                Section {
                    noSaleSummaryRow(count: todayNoSales)
                        .listRowBackground(Color.bizarreWarning.opacity(0.08))
                } header: {
                    Text("Today's no-sale activity")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            ForEach(groupedByDay, id: \.day) { group in
                Section(group.dayLabel) {
                    ForEach(group.entries) { entry in
                        AuditEntryRow(entry: entry)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - §16 Manager override summary row

    /// Count of manager_override events from today.
    private var managerOverrideCountToday: Int {
        let calendar = Calendar.current
        return entries.filter {
            $0.eventType == PosAuditEntry.EventType.managerOverride &&
            calendar.isDateInToday($0.date)
        }.count
    }

    /// Prominent summary row shown when there are manager override events today.
    private func managerOverrideSummaryRow(count: Int) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Manager overrides today")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("A manager bypassed a system limit or policy.")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text("\(count)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(count > 2 ? Color.bizarreError : Color.bizarreWarning)
                .monospacedDigit()
                .accessibilityLabel("\(count) manager override events today")
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pos.auditLog.managerOverrideSummary")
    }

    // MARK: - §39 No-sale summary row

    /// Count of no-sale events from today (calendar day of the device).
    private var noSaleCountToday: Int {
        let calendar = Calendar.current
        return entries.filter {
            $0.eventType == PosAuditEntry.EventType.noSale &&
            calendar.isDateInToday($0.date)
        }.count
    }

    /// Prominent summary row shown at the top of the audit list when there
    /// are no-sale events today. Highlights the count with the warning color
    /// and uses an SF Symbol for quick scanability.
    private func noSaleSummaryRow(count: Int) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No-sale drawer opens today")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Cashier opened drawer without completing a sale.")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text("\(count)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(count > 2 ? Color.bizarreError : Color.bizarreWarning)
                .monospacedDigit()
                .accessibilityLabel("\(count) no-sale events today")
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pos.auditLog.noSaleSummary")
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No audit events yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Events are recorded when cashiers void lines, apply overrides, or open the drawer without a sale.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("pos.auditLog.empty")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Could not load audit log")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadEntries() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.base)
    }

    // MARK: - Data

    private func loadEntries() async {
        isLoading = true
        loadError = nil
        do {
            entries = try await PosAuditLogStore.shared.recent(limit: 50)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Grouping

    private struct DayGroup {
        let day: Date          // midnight of the day (for identity)
        let dayLabel: String
        let entries: [PosAuditEntry]
    }

    private var groupedByDay: [DayGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.date)
        }
        return grouped.sorted { $0.key > $1.key }.map { (day, items) in
            let label = calendar.isDateInToday(day) ? "Today"
                      : calendar.isDateInYesterday(day) ? "Yesterday"
                      : formatter.string(from: day)
            return DayGroup(day: day, dayLabel: label, entries: items)
        }
    }
}

// MARK: - Row

private struct AuditEntryRow: View {
    let entry: PosAuditEntry

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            eventBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.eventTypeLabel)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    if let amount = entry.amountCents {
                        Text(CartMath.formatCents(amount))
                            .font(.brandBodyMedium().monospacedDigit())
                            .foregroundStyle(.bizarreOrange)
                    }
                }
                idRow
                if let reason = entry.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
                Text(relativeTime)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var eventBadge: some View {
        Text(badgeLabel)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
    }

    private var idRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Label("Cashier \(entry.cashierId)", systemImage: "person")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if let managerId = entry.managerId {
                Label("Manager \(managerId)", systemImage: "person.badge.shield.checkmark")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.date, relativeTo: Date())
    }

    private var badgeLabel: String {
        switch entry.eventType {
        case "void_line":               return "VOID"
        case "no_sale":                 return "NO SALE"
        case "discount_override":       return "DISC OVR"
        case "price_override":          return "PRICE OVR"
        case "delete_line":             return "DELETE"
        case "manager_approved_refund": return "REFUND"
        case "cash_drop":               return "DROP"
        case "drawer_open":             return "DRAWER"
        case "manager_override":        return "MGR OVR"
        default:                        return entry.eventType.uppercased()
        }
    }

    private var badgeColor: Color {
        switch entry.eventType {
        case "void_line":               return .red
        case "no_sale":                 return .bizarreWarning
        case "discount_override":       return .purple
        case "price_override":          return .indigo
        case "delete_line":             return .red
        case "manager_approved_refund": return .orange
        case "cash_drop":               return .teal
        case "drawer_open":             return .teal
        case "manager_override":        return .bizarreWarning
        default:                        return .gray
        }
    }
}

private extension Font {
    static func brandBodySmall() -> Font { .system(size: 11) }
}
#endif
