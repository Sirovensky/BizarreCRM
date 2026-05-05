#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5.7 Unified Customer Activity Timeline
//
// Vertical chronological timeline with colored dots per event type.
// Filter chips narrow by event kind; jump-to-date picker scrolls list.
// Metrics header: LTV, last visit, avg spend, repeat rate, preferred
// services, churn risk score — all derived from the loaded entries.

// MARK: - Event kinds

public enum CustomerTimelineEventKind: String, CaseIterable, Sendable {
    case ticket       = "ticket"
    case invoice      = "invoice"
    case payment      = "payment"
    case sms          = "sms"
    case email        = "email"
    case appointment  = "appointment"
    case note         = "note"
    case feedback     = "feedback"

    var label: String {
        switch self {
        case .ticket:      return "Tickets"
        case .invoice:     return "Invoices"
        case .payment:     return "Payments"
        case .sms:         return "SMS"
        case .email:       return "Email"
        case .appointment: return "Appointments"
        case .note:        return "Notes"
        case .feedback:    return "Feedback"
        }
    }

    var icon: String {
        switch self {
        case .ticket:      return "ticket"
        case .invoice:     return "doc.text"
        case .payment:     return "creditcard"
        case .sms:         return "message"
        case .email:       return "envelope"
        case .appointment: return "calendar"
        case .note:        return "note.text"
        case .feedback:    return "star.bubble"
        }
    }

    var dotColor: Color {
        switch self {
        case .ticket:      return .bizarreOrange
        case .invoice:     return .bizarreTeal
        case .payment:     return .bizarreSuccess
        case .sms:         return .blue
        case .email:       return .purple
        case .appointment: return .indigo
        case .note:        return .orange
        case .feedback:    return .bizarreWarning
        }
    }
}

// MARK: - DTO

public struct CustomerTimelineEvent: Decodable, Identifiable, Sendable {
    public let id: String
    public let kind: CustomerTimelineEventKind
    public let title: String
    public let subtitle: String?
    public let amountCents: Int?
    public let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle
        case amountCents = "amount_cents"
        case occurredAt  = "occurred_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        let raw    = try c.decode(String.self, forKey: .kind)
        kind       = CustomerTimelineEventKind(rawValue: raw) ?? .note
        title      = try c.decode(String.self, forKey: .title)
        subtitle   = try c.decodeIfPresent(String.self, forKey: .subtitle)
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents)
        let iso    = try c.decode(String.self, forKey: .occurredAt)
        occurredAt = ISO8601DateFormatter().date(from: iso) ?? Date.distantPast
    }
}

// MARK: - Metrics header DTO

public struct CustomerTimelineMetrics: Sendable {
    public let ltvCents: Int
    public let lastVisitLabel: String
    public let avgSpendCents: Int
    public let repeatRate: Double          // 0–1
    public let preferredServices: [String]
    public let churnRiskLabel: String
}

// MARK: - ViewModel

@MainActor
@Observable
public final class CustomerActivityTimelineViewModel {
    public var events: [CustomerTimelineEvent] = []
    public var isLoading = false
    public var errorMessage: String?

    // Filter / jump
    public var activeFilters: Set<CustomerTimelineEventKind> = []
    public var jumpDate: Date? = nil

    // Metrics (computed after load)
    public private(set) var metrics: CustomerTimelineMetrics?

    private let customerId: Int64
    private let api: APIClient

    public init(customerId: Int64, api: APIClient) {
        self.customerId = customerId
        self.api = api
    }

    public var filtered: [CustomerTimelineEvent] {
        var result = events
        if !activeFilters.isEmpty {
            result = result.filter { activeFilters.contains($0.kind) }
        }
        if let target = jumpDate {
            // Partition so nearest date to target comes first
            result = result.sorted {
                abs($0.occurredAt.timeIntervalSince(target)) <
                abs($1.occurredAt.timeIntervalSince(target))
            }
        }
        return result
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            events = try await api.customerTimeline(customerId: customerId)
            metrics = buildMetrics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggleFilter(_ kind: CustomerTimelineEventKind) {
        if activeFilters.contains(kind) {
            activeFilters.remove(kind)
        } else {
            activeFilters.insert(kind)
        }
        // Clear jump when filter changes
        jumpDate = nil
    }

    private func buildMetrics() -> CustomerTimelineMetrics {
        let payments = events.filter { $0.kind == .payment }
        let totalCents = payments.compactMap(\.amountCents).reduce(0, +)
        let lastVisit: String = {
            if let last = events.max(by: { $0.occurredAt < $1.occurredAt }) {
                let f = RelativeDateTimeFormatter()
                f.unitsStyle = .short
                return f.localizedString(for: last.occurredAt, relativeTo: Date())
            }
            return "Never"
        }()
        let avgSpend = payments.isEmpty ? 0 : totalCents / payments.count
        let uniqueDays = Set(payments.map {
            Calendar.current.startOfDay(for: $0.occurredAt)
        }).count
        let repeatRate: Double = payments.count > 1 ? min(Double(uniqueDays - 1) / Double(max(uniqueDays, 1)), 1.0) : 0

        // Preferred services: ticket titles appearing most
        let ticketTitles = events.filter { $0.kind == .ticket }.map(\.title)
        let freq = ticketTitles.reduce(into: [:] as [String: Int]) { $0[$1, default: 0] += 1 }
        let preferred = freq.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        // Churn risk heuristic
        let daysSinceLast = events.max(by: { $0.occurredAt < $1.occurredAt })
            .map { Int(-$0.occurredAt.timeIntervalSinceNow / 86400) } ?? 999
        let churnLabel: String
        switch daysSinceLast {
        case ..<60:  churnLabel = "Low"
        case ..<120: churnLabel = "Medium"
        default:     churnLabel = "High"
        }

        return CustomerTimelineMetrics(
            ltvCents: totalCents,
            lastVisitLabel: lastVisit,
            avgSpendCents: avgSpend,
            repeatRate: repeatRate,
            preferredServices: Array(preferred),
            churnRiskLabel: churnLabel
        )
    }
}

// MARK: - Main view

public struct CustomerActivityTimelineView: View {
    @State private var vm: CustomerActivityTimelineViewModel
    @State private var showingDatePicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(customerId: Int64, api: APIClient) {
        _vm = State(wrappedValue: CustomerActivityTimelineViewModel(customerId: customerId, api: api))
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    // Metrics header
                    if let m = vm.metrics {
                        Section {
                            TimelineMetricsHeader(metrics: m)
                                .padding(.horizontal, BrandSpacing.base)
                                .padding(.top, BrandSpacing.sm)
                        }
                    }

                    // Filter chips
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: BrandSpacing.xs) {
                                ForEach(CustomerTimelineEventKind.allCases, id: \.rawValue) { kind in
                                    filterChip(kind)
                                }
                            }
                            .padding(.horizontal, BrandSpacing.base)
                            .padding(.vertical, BrandSpacing.xs)
                        }
                    } header: {
                        HStack {
                            Text("Activity")
                                .font(.brandTitleMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            Button {
                                showingDatePicker.toggle()
                            } label: {
                                Label("Jump to date", systemImage: "calendar.badge.clock")
                                    .font(.brandLabelLarge())
                                    .foregroundStyle(.bizarreOrange)
                            }
                            .accessibilityLabel("Jump to date in timeline")
                        }
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.sm)
                        .background(.ultraThinMaterial)
                    }

                    // Timeline rows
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else if let err = vm.errorMessage {
                        ContentUnavailableView(err,
                            systemImage: "exclamationmark.triangle",
                            description: Text("Pull to refresh"))
                            .padding(.top, BrandSpacing.xl)
                    } else if vm.filtered.isEmpty {
                        ContentUnavailableView("No activity",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("No events match the current filter."))
                            .padding(.top, BrandSpacing.xl)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(vm.filtered.enumerated()), id: \.element.id) { idx, event in
                                timelineRow(event: event, isLast: idx == vm.filtered.count - 1)
                                    .id(event.id)
                            }
                        }
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.bottom, BrandSpacing.xl)
                    }
                }
            }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showingDatePicker) {
                DatePickerSheet(selection: Binding(
                    get: { vm.jumpDate ?? Date() },
                    set: { vm.jumpDate = $0 }
                )) {
                    showingDatePicker = false
                    // Scroll to nearest event after short delay
                    if let first = vm.filtered.first {
                        withAnimation(reduceMotion ? nil : .easeInOut) {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Filter chip

    private func filterChip(_ kind: CustomerTimelineEventKind) -> some View {
        let isActive = vm.activeFilters.contains(kind)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                vm.toggleFilter(kind)
            }
        } label: {
            HStack(spacing: BrandSpacing.xxs) {
                Circle()
                    .fill(kind.dotColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(kind.label)
                    .font(.brandLabelLarge())
                    .foregroundStyle(isActive ? .white : .bizarreOnSurface)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(isActive ? kind.dotColor : Color.bizarreSurface1, in: Capsule())
            .overlay(Capsule().strokeBorder(
                isActive ? kind.dotColor : Color.bizarreOutline.opacity(0.4),
                lineWidth: isActive ? 0 : 0.5
            ))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.label) filter \(isActive ? "on" : "off")")
    }

    // MARK: - Timeline row

    private func timelineRow(event: CustomerTimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            // Dot + line
            VStack(spacing: 0) {
                Circle()
                    .fill(event.kind.dotColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                if !isLast {
                    Rectangle()
                        .fill(Color.bizarreOutline.opacity(0.3))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            // Content
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        if let sub = event.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let cents = event.amountCents, cents != 0 {
                            Text(formatCents(cents))
                                .font(.brandMono(size: 13))
                                .foregroundStyle(cents > 0 ? .bizarreSuccess : .bizarreError)
                                .monospacedDigit()
                        }
                        Text(shortDate(event.occurredAt))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Divider().opacity(0.4).padding(.top, BrandSpacing.xxs)
            }
            .padding(.bottom, BrandSpacing.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(buildA11yLabel(event))
    }

    // MARK: - Helpers

    private func formatCents(_ cents: Int) -> String {
        let val = Double(abs(cents)) / 100
        let sign = cents < 0 ? "-" : ""
        return "\(sign)$\(String(format: "%.2f", val))"
    }

    private func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }

    private func buildA11yLabel(_ e: CustomerTimelineEvent) -> String {
        var parts = [e.kind.label, e.title]
        if let sub = e.subtitle { parts.append(sub) }
        if let cents = e.amountCents { parts.append(formatCents(cents)) }
        parts.append(shortDate(e.occurredAt))
        return parts.joined(separator: ". ")
    }
}

// MARK: - Metrics header sub-view

private struct TimelineMetricsHeader: View {
    let metrics: CustomerTimelineMetrics

    private var ltvFormatted: String {
        "$\(metrics.ltvCents / 100)"
    }
    private var avgSpendFormatted: String {
        "$\(metrics.avgSpendCents / 100)"
    }
    private var repeatPct: String {
        "\(Int(metrics.repeatRate * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Overview")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: BrandSpacing.sm) {
                metricTile("LTV", value: ltvFormatted, icon: "dollarsign.circle")
                metricTile("Last Visit", value: metrics.lastVisitLabel, icon: "clock")
                metricTile("Avg Spend", value: avgSpendFormatted, icon: "cart")
                metricTile("Repeat Rate", value: repeatPct, icon: "arrow.clockwise")
                metricTile("Churn Risk", value: metrics.churnRiskLabel, icon: "exclamationmark.triangle",
                           valueColor: churnColor)
                if !metrics.preferredServices.isEmpty {
                    metricTile("Preferred", value: metrics.preferredServices.first ?? "—",
                               icon: "wrench.and.screwdriver")
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var churnColor: Color {
        switch metrics.churnRiskLabel {
        case "Low":    return .bizarreSuccess
        case "Medium": return .bizarreWarning
        default:       return .bizarreError
        }
    }

    private func metricTile(_ label: String, value: String, icon: String,
                             valueColor: Color = .bizarreOnSurface) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(value)
                .font(.brandBodyMedium().weight(.semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Date picker sheet

private struct DatePickerSheet: View {
    @Binding var selection: Date
    var onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            DatePicker("Jump to date", selection: $selection,
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(.bizarreOrange)
                .padding(BrandSpacing.base)
                .navigationTitle("Jump to Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") { onConfirm() }
                            .fontWeight(.semibold)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { onConfirm() }
                    }
                }
        }
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `GET /api/v1/customers/:id/timeline` — unified activity events.
    public func customerTimeline(customerId: Int64) async throws -> [CustomerTimelineEvent] {
        try await get("/api/v1/customers/\(customerId)/timeline",
                      as: [CustomerTimelineEvent].self)
    }
}

#endif
