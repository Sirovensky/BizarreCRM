#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5 Customer Complaint Intake + Resolution Flow
//
// - Intake via customer detail → "New complaint"
// - Fields: category + severity + description + linked ticket
// - Resolution flow: assignee + due date + escalation path
// - Status: open / investigating / resolved / rejected
// - Required root cause on resolve: product / service / communication / billing / other
// - SLA: response within 24h / resolution within 7d, with breach alerts
// - Full audit history; immutable once closed

// MARK: - Models

public enum ComplaintStatus: String, Codable, Sendable, CaseIterable {
    case open          = "open"
    case investigating = "investigating"
    case resolved      = "resolved"
    case rejected      = "rejected"

    var label: String {
        switch self {
        case .open:          return "Open"
        case .investigating: return "Investigating"
        case .resolved:      return "Resolved"
        case .rejected:      return "Rejected"
        }
    }

    var color: Color {
        switch self {
        case .open:          return .bizarreError
        case .investigating: return .bizarreWarning
        case .resolved:      return .bizarreSuccess
        case .rejected:      return .bizarreOnSurfaceMuted
        }
    }

    var icon: String {
        switch self {
        case .open:          return "exclamationmark.circle.fill"
        case .investigating: return "magnifyingglass.circle.fill"
        case .resolved:      return "checkmark.circle.fill"
        case .rejected:      return "xmark.circle.fill"
        }
    }
}

public enum ComplaintCategory: String, Codable, Sendable, CaseIterable {
    case product      = "product"
    case service      = "service"
    case communication = "communication"
    case billing      = "billing"
    case other        = "other"

    var label: String { rawValue.capitalized }
}

public enum ComplaintSeverity: Int, Codable, Sendable, CaseIterable {
    case low    = 1
    case medium = 2
    case high   = 3
    case critical = 4

    var label: String {
        switch self {
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .low:      return .bizarreSuccess
        case .medium:   return .bizarreWarning
        case .high:     return .orange
        case .critical: return .bizarreError
        }
    }
}

public struct CustomerComplaint: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let customerId: Int64
    public let category: ComplaintCategory
    public let severity: ComplaintSeverity
    public let description: String
    public let linkedTicketId: Int64?
    public let status: ComplaintStatus
    public let assigneeName: String?
    public let dueAt: String?
    public let rootCause: ComplaintCategory?
    public let createdAt: String
    public let slaBreached: Bool

    enum CodingKeys: String, CodingKey {
        case id, category, severity, description, status
        case customerId    = "customer_id"
        case linkedTicketId = "linked_ticket_id"
        case assigneeName  = "assignee_name"
        case dueAt         = "due_at"
        case rootCause     = "root_cause"
        case createdAt     = "created_at"
        case slaBreached   = "sla_breached"
    }
}

// MARK: - New complaint intake sheet

public struct CustomerNewComplaintSheet: View {
    let customerId: Int64
    let api: APIClient
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var category: ComplaintCategory = .service
    @State private var severity: ComplaintSeverity = .medium
    @State private var description = ""
    @State private var linkedTicketId: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    public init(customerId: Int64, api: APIClient, onSaved: (() -> Void)? = nil) {
        self.customerId = customerId
        self.api = api
        self.onSaved = onSaved
    }

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Category & Severity") {
                    Picker("Category", selection: $category) {
                        ForEach(ComplaintCategory.allCases, id: \.rawValue) {
                            Text($0.label).tag($0)
                        }
                    }
                    Picker("Severity", selection: $severity) {
                        ForEach(ComplaintSeverity.allCases, id: \.rawValue) {
                            Label($0.label, systemImage: $0 == .critical ? "exclamationmark.2" : "exclamationmark")
                                .tag($0)
                        }
                    }
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .font(.brandBodyMedium())
                        .frame(minHeight: 100)
                        .accessibilityLabel("Complaint description")
                }

                Section {
                    TextField("Ticket # (optional)", text: $linkedTicketId)
                        .keyboardType(.numberPad)
                        .font(.brandMono(size: 15))
                        .accessibilityLabel("Linked ticket ID")
                } header: {
                    Text("Linked Ticket")
                } footer: {
                    Text("SLA: response within 24h, resolution within 7d. Breaches trigger staff alerts.")
                        .font(.brandLabelSmall())
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .navigationTitle("New Complaint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submit() } }
                        .fontWeight(.semibold)
                        .disabled(!isValid || isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(isSaving)
        }
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let ticketId = Int64(linkedTicketId.trimmingCharacters(in: .whitespacesAndNewlines))
            try await api.createCustomerComplaint(
                customerId: customerId,
                category: category,
                severity: severity,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                linkedTicketId: ticketId
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Complaint list view (in customer detail)

public struct CustomerComplaintsSection: View {
    let customerId: Int64
    let api: APIClient

    @State private var complaints: [CustomerComplaint] = []
    @State private var isLoading = false
    @State private var showingNewSheet = false
    @State private var selectedComplaint: CustomerComplaint?

    public init(customerId: Int64, api: APIClient) {
        self.customerId = customerId
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "exclamationmark.bubble")
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Complaints")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)

                if complaints.contains(where: \.slaBreached) {
                    slaBreachBadge
                }

                Spacer()
                Button {
                    showingNewSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Log new complaint")
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            } else if complaints.isEmpty {
                Text("No complaints on record.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(complaints) { c in
                    complaintRow(c)
                    if c.id != complaints.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await load() }
        .sheet(isPresented: $showingNewSheet) {
            CustomerNewComplaintSheet(customerId: customerId, api: api) {
                Task { await load() }
            }
        }
        .sheet(item: $selectedComplaint) { complaint in
            ComplaintDetailSheet(complaint: complaint, api: api) {
                Task { await load() }
            }
        }
    }

    private var slaBreachBadge: some View {
        Text("SLA Breached")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.bizarreError, in: Capsule())
            .accessibilityLabel("SLA breach on one or more complaints")
    }

    private func complaintRow(_ c: CustomerComplaint) -> some View {
        Button {
            selectedComplaint = c
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: c.status.icon)
                    .foregroundStyle(c.status.color)
                    .font(.system(size: 18))
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(c.category.label)
                            .font(.brandLabelLarge().weight(.semibold))
                            .foregroundStyle(.bizarreOnSurface)
                        severityChip(c.severity)
                    }
                    Text(c.description)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(c.status.label)
                        .font(.brandLabelSmall())
                        .foregroundStyle(c.status.color)
                    if c.slaBreached {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.category.label) complaint, \(c.severity.label) severity, \(c.status.label). \(c.slaBreached ? "SLA breached." : "")")
    }

    private func severityChip(_ severity: ComplaintSeverity) -> some View {
        Text(severity.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(severity.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(severity.color.opacity(0.12), in: Capsule())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        complaints = (try? await api.customerComplaints(customerId: customerId)) ?? []
    }
}

// MARK: - Complaint detail + resolution sheet

struct ComplaintDetailSheet: View {
    let complaint: CustomerComplaint
    let api: APIClient
    var onUpdated: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var rootCause: ComplaintCategory = .service
    @State private var isResolving = false
    @State private var isRejecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Summary") {
                    LabeledContent("Category", value: complaint.category.label)
                    LabeledContent("Severity", value: complaint.severity.label)
                    LabeledContent("Status", value: complaint.status.label)
                    if let assignee = complaint.assigneeName {
                        LabeledContent("Assignee", value: assignee)
                    }
                    if let due = complaint.dueAt {
                        LabeledContent("Due", value: String(due.prefix(10)))
                    }
                }

                Section("Description") {
                    Text(complaint.description)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                }

                if complaint.status == .open || complaint.status == .investigating {
                    Section {
                        Picker("Root cause", selection: $rootCause) {
                            ForEach(ComplaintCategory.allCases, id: \.rawValue) {
                                Text($0.label).tag($0)
                            }
                        }
                    } header: {
                        Text("Resolution")
                    } footer: {
                        Text("Root cause is required before marking as resolved. Audit trail is immutable once closed.")
                            .font(.brandLabelSmall())
                    }

                    Section {
                        Button {
                            Task { await resolve() }
                        } label: {
                            HStack {
                                if isResolving { ProgressView().tint(.white) }
                                Label("Mark Resolved", systemImage: "checkmark.circle")
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreSuccess)
                        .disabled(isResolving || isRejecting)

                        Button(role: .destructive) {
                            Task { await reject() }
                        } label: {
                            HStack {
                                if isRejecting { ProgressView() }
                                Label("Reject", systemImage: "xmark.circle")
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isResolving || isRejecting)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .navigationTitle("Complaint #\(complaint.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func resolve() async {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }
        do {
            try await api.resolveCustomerComplaint(
                complaintId: complaint.id, rootCause: rootCause)
            onUpdated?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reject() async {
        isRejecting = true
        errorMessage = nil
        defer { isRejecting = false }
        do {
            try await api.rejectCustomerComplaint(complaintId: complaint.id)
            onUpdated?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - APIClient extensions

extension APIClient {
    /// `GET /api/v1/customers/:id/complaints`
    public func customerComplaints(customerId: Int64) async throws -> [CustomerComplaint] {
        try await get("/api/v1/customers/\(customerId)/complaints",
                      as: [CustomerComplaint].self)
    }

    /// `POST /api/v1/customers/:id/complaints`
    public func createCustomerComplaint(
        customerId: Int64,
        category: ComplaintCategory,
        severity: ComplaintSeverity,
        description: String,
        linkedTicketId: Int64?
    ) async throws {
        _ = try await post(
            "/api/v1/customers/\(customerId)/complaints",
            body: ComplaintCreateBody(
                category: category.rawValue,
                severity: severity.rawValue,
                description: description,
                linked_ticket_id: linkedTicketId
            ),
            as: EmptyResponse.self
        )
    }

    /// `POST /api/v1/complaints/:id/resolve`
    public func resolveCustomerComplaint(
        complaintId: Int64,
        rootCause: ComplaintCategory
    ) async throws {
        _ = try await post(
            "/api/v1/complaints/\(complaintId)/resolve",
            body: ComplaintResolveBody(root_cause: rootCause.rawValue),
            as: EmptyResponse.self
        )
    }

    /// `POST /api/v1/complaints/:id/reject`
    public func rejectCustomerComplaint(complaintId: Int64) async throws {
        _ = try await post(
            "/api/v1/complaints/\(complaintId)/reject",
            body: ComplaintEmptyBody(),
            as: EmptyResponse.self
        )
    }
}

private struct ComplaintEmptyBody: Encodable, Sendable {}

private struct ComplaintCreateBody: Encodable, Sendable {
    let category: String
    let severity: Int
    let description: String
    let linked_ticket_id: Int64?
}

private struct ComplaintResolveBody: Encodable, Sendable {
    let root_cause: String
}

#endif
