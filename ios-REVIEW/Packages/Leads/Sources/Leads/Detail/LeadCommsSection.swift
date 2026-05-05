#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.3 Lead detail — Communications tab section
// SMS + email + call log timeline; "Send new SMS / email" CTAs.

/// Embedded timeline of all communications for a lead.
/// Loaded from `GET /leads/:id/communications` which returns a unified log.
public struct LeadCommsSection: View {
    let leadId: Int64
    let leadPhone: String?
    let leadEmail: String?
    let api: APIClient

    @State private var entries: [LeadCommEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingSMSCompose = false
    @State private var showingEmailCompose = false

    public init(leadId: Int64, leadPhone: String?, leadEmail: String?, api: APIClient) {
        self.leadId = leadId
        self.leadPhone = leadPhone
        self.leadEmail = leadEmail
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header + CTAs
            HStack {
                Text("COMMUNICATIONS")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: BrandSpacing.sm) {
                    if leadPhone != nil {
                        Button {
                            showingSMSCompose = true
                        } label: {
                            Label("SMS", systemImage: "message.fill")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 16))
                                .foregroundStyle(.bizarreOrange)
                        }
                        .accessibilityLabel("Send SMS to lead")
                    }
                    if leadEmail != nil {
                        Button {
                            showingEmailCompose = true
                        } label: {
                            Label("Email", systemImage: "envelope.fill")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 16))
                                .foregroundStyle(.bizarreOrange)
                        }
                        .accessibilityLabel("Send email to lead")
                    }
                }
            }

            // Timeline
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .accessibilityLabel("Loading communications")
            } else if let err = error {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            } else if entries.isEmpty {
                Text("No communications yet. Send an SMS or email to start.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.vertical, BrandSpacing.sm)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        LeadCommRow(entry: entry)
                        if entry.id != entries.last?.id {
                            Divider().padding(.leading, 38)
                        }
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await load() }
        .sheet(isPresented: $showingSMSCompose) {
            if let phone = leadPhone {
                LeadQuickSMSSheet(phone: phone, api: api)
            }
        }
        .sheet(isPresented: $showingEmailCompose) {
            if let email = leadEmail {
                LeadQuickEmailSheet(email: email, api: api)
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            entries = try await api.leadCommunications(id: leadId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct LeadCommRow: View {
    let entry: LeadCommEntry

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(.bizarreOrange)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(3)
                }
                if let date = entry.createdAt {
                    Text(String(date.prefix(16)))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.kind ?? "message"): \(entry.body ?? ""). \(entry.createdAt.map { String($0.prefix(10)) } ?? "")")
    }

    private var iconName: String {
        switch (entry.kind ?? "").lowercased() {
        case "sms":   return "message.fill"
        case "email": return "envelope.fill"
        case "call":  return "phone.fill"
        default:      return "bubble.left.fill"
        }
    }
}

// MARK: - Quick compose sheets

private struct LeadQuickSMSSheet: View {
    let phone: String
    let api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                Text("To: \(phone)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextEditor(text: $messageText)
                    .font(.brandBodyMedium())
                    .frame(minHeight: 120)
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
                    .accessibilityLabel("SMS message body")
                if let err = error {
                    Text(err).font(.brandLabelSmall()).foregroundStyle(.bizarreError)
                }
                Spacer()
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Send SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func send() async {
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            _ = try await api.sendSms(to: phone, message: messageText)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct LeadQuickEmailSheet: View {
    let email: String
    let api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("To: \(email)")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("Subject", text: $subject)
                        .accessibilityLabel("Email subject")
                }
                Section("Body") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 100)
                        .accessibilityLabel("Email body")
                }
                if let err = error {
                    Section { Text(err).foregroundStyle(.bizarreError).font(.brandLabelSmall()) }
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Send Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending { ProgressView() }
                    else {
                        Button("Send") { Task { await send() } }
                            .disabled(subject.isEmpty || bodyText.isEmpty)
                    }
                }
            }
        }
    }

    private func send() async {
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            try await api.sendLeadEmail(to: email, subject: subject, body: bodyText)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Model

public struct LeadCommEntry: Identifiable, Decodable, Sendable {
    public let id: Int64
    public let kind: String?
    public let body: String?
    public let createdAt: String?
    public let direction: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, body, direction
        case createdAt = "created_at"
    }
}

// MARK: - Endpoints

extension APIClient {
    /// `GET /leads/:id/communications` — unified SMS/email/call log for a lead.
    public func leadCommunications(id: Int64) async throws -> [LeadCommEntry] {
        try await get("/leads/\(id)/communications", as: [LeadCommEntry].self)
    }

    /// `POST /emails/send` wrapper used from lead detail quick-compose.
    public func sendLeadEmail(to email: String, subject: String, body: String) async throws {
        _ = try await post("/emails/send", body: LeadEmailBody(to: email, subject: subject, body: body), as: EmptyResponse.self)
    }
}

private struct LeadEmailBody: Encodable, Sendable {
    let to: String
    let subject: String
    let body: String
}

#endif
