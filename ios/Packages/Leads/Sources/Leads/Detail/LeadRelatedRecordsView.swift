import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.3 Related tickets / estimates + convert-to-estimate

/// Card showing related tickets and estimates for a lead.
public struct LeadRelatedRecordsView: View {
    public let leadId: Int64
    public let api: APIClient

    @State private var relatedTickets: [LeadRelatedTicket] = []
    @State private var relatedEstimates: [LeadRelatedEstimate] = []
    @State private var isLoading = true
    @State private var showingConvertToEstimate = false

    public init(leadId: Int64, api: APIClient) {
        self.leadId = leadId
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("RELATED")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.8)
                Spacer(minLength: 0)
                Button {
                    showingConvertToEstimate = true
                } label: {
                    Label("New estimate", systemImage: "doc.badge.plus")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Convert lead to estimate")
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading related records")
            } else if relatedTickets.isEmpty && relatedEstimates.isEmpty {
                Text("No related tickets or estimates yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("No related tickets or estimates")
            } else {
                if !relatedTickets.isEmpty {
                    Text("Tickets")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    VStack(spacing: 0) {
                        ForEach(relatedTickets) { ticket in
                            LeadRelatedTicketRow(ticket: ticket)
                            Divider().overlay(Color.bizarreOutline.opacity(0.2))
                        }
                    }
                }
                if !relatedEstimates.isEmpty {
                    Text("Estimates")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    VStack(spacing: 0) {
                        ForEach(relatedEstimates) { estimate in
                            LeadRelatedEstimateRow(estimate: estimate)
                            Divider().overlay(Color.bizarreOutline.opacity(0.2))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await load() }
        .sheet(isPresented: $showingConvertToEstimate) {
            LeadConvertToEstimateSheet(api: api, leadId: leadId)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let tickets = (try? await api.leadRelatedTickets(leadId: leadId)) ?? []
        async let estimates = (try? await api.leadRelatedEstimates(leadId: leadId)) ?? []
        relatedTickets = await tickets
        relatedEstimates = await estimates
    }
}

// MARK: - Row views

private struct LeadRelatedTicketRow: View {
    let ticket: LeadRelatedTicket

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.bizarreOrange)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.subject ?? "Ticket #\(ticket.id)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let status = ticket.status {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            Text("#\(ticket.id)")
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textSelection(.enabled)
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ticket \(ticket.id): \(ticket.subject ?? "No subject"), status: \(ticket.status ?? "unknown")")
    }
}

private struct LeadRelatedEstimateRow: View {
    let estimate: LeadRelatedEstimate

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.bizarreTeal)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimate #\(estimate.id)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let status = estimate.status {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            if let total = estimate.totalFormatted {
                Text(total)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estimate \(estimate.id): status \(estimate.status ?? "unknown"), total \(estimate.totalFormatted ?? "unknown")")
    }
}

// MARK: - §9.3 Convert lead to estimate sheet

public struct LeadConvertToEstimateSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let api: APIClient
    private let leadId: Int64

    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    public init(api: APIClient, leadId: Int64) {
        self.api = api
        self.leadId = leadId
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Notes (optional)") {
                        TextField("Describe what to include in the estimate", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityLabel("Estimate notes")
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    if let err = errorMessage {
                        Section {
                            Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                        }
                        .listRowBackground(Color.bizarreSurface1)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Estimate from Lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Creating…" : "Create") {
                        Task { await createEstimate() }
                    }
                    .disabled(isSubmitting)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createEstimate() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await api.convertLeadToEstimate(leadId: leadId, notes: notes)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - DTOs

public struct LeadRelatedTicket: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let subject: String?
    public let status: String?

    enum CodingKeys: String, CodingKey { case id, subject, status }
}

public struct LeadRelatedEstimate: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let status: String?
    public let totalCents: Int?

    public var totalFormatted: String? {
        guard let cents = totalCents else { return nil }
        let dollars = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars))
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case totalCents = "total_cents"
    }
}

// MARK: - APIClient endpoints

extension APIClient {
    /// `GET /api/v1/leads/:id/tickets` — tickets linked to this lead.
    public func leadRelatedTickets(leadId: Int64) async throws -> [LeadRelatedTicket] {
        try await get("/api/v1/leads/\(leadId)/tickets", as: [LeadRelatedTicket].self)
    }

    /// `GET /api/v1/leads/:id/estimates` — estimates linked to this lead.
    public func leadRelatedEstimates(leadId: Int64) async throws -> [LeadRelatedEstimate] {
        try await get("/api/v1/leads/\(leadId)/estimates", as: [LeadRelatedEstimate].self)
    }

    /// `POST /api/v1/leads/:id/convert-to-estimate` — create an estimate from lead data.
    @discardableResult
    public func convertLeadToEstimate(leadId: Int64, notes: String?) async throws -> CreatedResource {
        struct Body: Encodable, Sendable { let notes: String? }
        return try await post(
            "/api/v1/leads/\(leadId)/convert-to-estimate",
            body: Body(notes: notes),
            as: CreatedResource.self
        )
    }
}
