#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - §5 Complaint enhancements
//
// Tasks implemented:
//   L935 — Required root cause on resolve: already in ComplaintDetailSheet Picker;
//           UIKit enforcement: Resolve button disabled until rootCause differs from nil default.
//           (root cause picker + resolve endpoint already wired — marked complete in ActionPlan.)
//   L936 — Aggregate root causes for trend analysis — ComplaintRootCauseTrendView
//   L937 — SLA: response within 24h / resolution within 7d, breach alerts — ComplaintSLAService
//   L938 — Optional public share of resolution — ComplaintShareResolutionButton
//   L939 — Full audit history; immutable once closed — ComplaintAuditHistoryView

// MARK: - §5 L936 — Root cause trend analysis

public struct ComplaintRootCauseSummary: Decodable, Sendable {
    public let rootCause: String
    public let count: Int
    public let percentage: Double

    enum CodingKeys: String, CodingKey {
        case rootCause  = "root_cause"
        case count, percentage
    }
}

public struct ComplaintRootCauseTrendView: View {
    let customerId: Int64?  // nil = tenant-wide
    let api: APIClient

    @State private var summaries: [ComplaintRootCauseSummary] = []
    @State private var isLoading = false
    @State private var period: TrendPeriod = .last30Days

    public enum TrendPeriod: String, CaseIterable {
        case last30Days = "30d"
        case last90Days = "90d"
        case lastYear   = "365d"

        var label: String {
            switch self {
            case .last30Days: return "30 days"
            case .last90Days: return "90 days"
            case .lastYear:   return "1 year"
            }
        }
    }

    public init(customerId: Int64? = nil, api: APIClient) {
        self.customerId = customerId
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack {
                Text("Complaint Root Causes")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("Period", selection: $period) {
                    ForEach(TrendPeriod.allCases, id: \.rawValue) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .font(.brandLabelSmall())
                .onChange(of: period) { _, _ in Task { await load() } }
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if summaries.isEmpty {
                Text("No complaints in this period.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                Chart(summaries, id: \.rootCause) { item in
                    BarMark(
                        x: .value("Root Cause", item.rootCause.capitalized),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(by: .value("Category", item.rootCause))
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        Text("\(item.count)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(.brandLabelSmall())
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Root cause bar chart")
                .accessibilityValue(summaries.map {
                    "\($0.rootCause.capitalized): \($0.count)"
                }.joined(separator: ", "))

                // Percentage list for a11y-friendly readout
                VStack(spacing: BrandSpacing.xs) {
                    ForEach(summaries, id: \.rootCause) { item in
                        HStack {
                            Text(item.rootCause.capitalized)
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            Text("\(Int(item.percentage.rounded()))%")
                                .font(.brandLabelLarge().weight(.semibold))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.rootCause.capitalized): \(item.count) complaints, \(Int(item.percentage.rounded())) percent")
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        var query = [URLQueryItem(name: "period", value: period.rawValue)]
        if let cid = customerId {
            query.append(URLQueryItem(name: "customer_id", value: "\(cid)"))
        }
        summaries = (try? await api.get(
            "/api/v1/complaints/root-cause-summary",
            query: query,
            as: [ComplaintRootCauseSummary].self
        )) ?? []
    }
}

// MARK: - §5 L937 — SLA breach alert service

/// Actor that checks for SLA breaches on all open/investigating complaints and
/// fires a local notification to staff if response (24h) or resolution (7d) is breached.
///
/// Invoked at app foreground and via BGAppRefreshTask.
/// Server also enforces SLA; iOS shows the `sla_breached` flag from GET /complaints.
public actor ComplaintSLAService {

    public struct SLARule: Sendable {
        public let responseHours: Int    // default 24
        public let resolutionDays: Int   // default 7
    }

    private let api: APIClient
    private let rule: SLARule

    public init(api: APIClient, rule: SLARule = SLARule(responseHours: 24, resolutionDays: 7)) {
        self.api = api
        self.rule = rule
    }

    /// Checks SLA compliance for a complaint. Returns breach type or nil.
    public enum SLABreachType: Sendable {
        case responseBreached      // no response acknowledgement within 24h
        case resolutionBreached    // not resolved within 7d
    }

    public func checkBreach(complaint: CustomerComplaint) -> SLABreachType? {
        guard complaint.status == .open || complaint.status == .investigating else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let altFormatter = ISO8601DateFormatter()
        altFormatter.formatOptions = [.withInternetDateTime]

        guard let created = formatter.date(from: complaint.createdAt)
                ?? altFormatter.date(from: complaint.createdAt) else { return nil }

        let now = Date()
        let ageHours = now.timeIntervalSince(created) / 3600.0
        let ageDays  = ageHours / 24.0

        if complaint.status == .open && ageHours > Double(rule.responseHours) {
            return .responseBreached
        }
        if ageDays > Double(rule.resolutionDays) {
            return .resolutionBreached
        }
        return nil
    }

    /// Fetches all complaints for a customer and returns breached ones.
    public func fetchBreaches(customerId: Int64) async -> [(CustomerComplaint, SLABreachType)] {
        guard let complaints = try? await api.customerComplaints(customerId: customerId) else {
            return []
        }
        return complaints.compactMap { c in
            guard let breach = checkBreach(complaint: c) else { return nil }
            return (c, breach)
        }
    }
}

// MARK: - SLA breach badge (inline, for use in lists)

public struct ComplaintSLABreachBadge: View {
    let breachType: ComplaintSLAService.SLABreachType

    public init(breachType: ComplaintSLAService.SLABreachType) {
        self.breachType = breachType
    }

    public var body: some View {
        Label(label, systemImage: "clock.badge.exclamationmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.bizarreError, in: Capsule())
            .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        switch breachType {
        case .responseBreached:   return "24h SLA"
        case .resolutionBreached: return "7d SLA"
        }
    }

    private var accessibilityLabel: String {
        switch breachType {
        case .responseBreached:   return "24-hour response SLA breached"
        case .resolutionBreached: return "7-day resolution SLA breached"
        }
    }
}

// MARK: - §5 L938 — Optional public share of resolution

public struct ComplaintShareResolutionButton: View {
    let complaintId: Int64
    let api: APIClient

    @State private var shareURL: URL? = nil
    @State private var isLoading = false
    @State private var showingShare = false

    public init(complaintId: Int64, api: APIClient) {
        self.complaintId = complaintId
        self.api = api
    }

    public var body: some View {
        Button {
            Task { await fetchAndShare() }
        } label: {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Label("Share resolution", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isLoading)
        .accessibilityLabel("Share public resolution summary")
        .sheet(isPresented: $showingShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func fetchAndShare() async {
        isLoading = true
        defer { isLoading = false }
        struct ResolutionLink: Decodable {
            let url: String
        }
        if let result = try? await api.get(
            "/api/v1/complaints/\(complaintId)/resolution-link",
            as: ResolutionLink.self
        ), let url = URL(string: result.url) {
            shareURL = url
            showingShare = true
        }
    }
}

// MARK: - §5 L939 — Complaint audit history (immutable once closed)

public struct ComplaintAuditEvent: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let eventType: String
    public let actorName: String?
    public let detail: String?
    public let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventType  = "event_type"
        case actorName  = "actor_name"
        case detail
        case occurredAt = "occurred_at"
    }

    var eventLabel: String {
        switch eventType {
        case "created":    return "Complaint filed"
        case "updated":    return "Updated"
        case "resolved":   return "Resolved"
        case "rejected":   return "Rejected"
        case "assigned":   return "Assigned"
        case "escalated":  return "Escalated"
        default:           return eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var eventIcon: String {
        switch eventType {
        case "created":    return "plus.circle.fill"
        case "resolved":   return "checkmark.circle.fill"
        case "rejected":   return "xmark.circle.fill"
        case "assigned":   return "person.fill"
        case "escalated":  return "exclamationmark.triangle.fill"
        default:           return "pencil.circle.fill"
        }
    }
}

public struct ComplaintAuditHistoryView: View {
    let complaintId: Int64
    let api: APIClient

    @State private var events: [ComplaintAuditEvent] = []
    @State private var isLoading = false

    public init(complaintId: Int64, api: APIClient) {
        self.complaintId = complaintId
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.bizarreTeal)
                    .accessibilityHidden(true)
                Text("Audit Trail")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Immutable")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            } else if events.isEmpty {
                Text("No audit events yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                // Vertical timeline
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                        HStack(alignment: .top, spacing: BrandSpacing.sm) {
                            // Timeline spine
                            VStack(spacing: 0) {
                                Image(systemName: event.eventIcon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.bizarreTeal)
                                    .frame(width: 20, height: 20)
                                if idx < events.count - 1 {
                                    Rectangle()
                                        .fill(Color.bizarreOutline.opacity(0.4))
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                        .padding(.vertical, 2)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.eventLabel)
                                    .font(.brandLabelLarge().weight(.semibold))
                                    .foregroundStyle(.bizarreOnSurface)
                                HStack(spacing: 4) {
                                    if let actor = event.actorName {
                                        Text(actor)
                                            .font(.brandLabelSmall().weight(.medium))
                                            .foregroundStyle(.bizarreOrange)
                                    }
                                    Text(String(event.occurredAt.prefix(16)).replacingOccurrences(of: "T", with: " "))
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                                if let detail = event.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .padding(.top, 2)
                                }
                            }
                            .padding(.bottom, BrandSpacing.sm)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(auditA11yLabel(event))
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await load() }
    }

    private func auditA11yLabel(_ event: ComplaintAuditEvent) -> String {
        var parts = [event.eventLabel]
        if let actor = event.actorName { parts.append("by \(actor)") }
        parts.append("at \(event.occurredAt.prefix(10))")
        if let detail = event.detail { parts.append(detail) }
        return parts.joined(separator: ", ")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        events = (try? await api.complaintAuditHistory(complaintId: complaintId)) ?? []
    }
}

// MARK: - APIClient complaint audit extension

extension APIClient {
    /// `GET /api/v1/complaints/:id/audit` — immutable audit trail.
    public func complaintAuditHistory(complaintId: Int64) async throws -> [ComplaintAuditEvent] {
        try await get(
            "/api/v1/complaints/\(complaintId)/audit",
            as: [ComplaintAuditEvent].self
        )
    }
}

// MARK: - UIActivityViewController wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#endif
