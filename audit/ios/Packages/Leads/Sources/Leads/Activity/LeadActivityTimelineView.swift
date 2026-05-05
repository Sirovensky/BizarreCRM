import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §9.3 Lead Activity Timeline
// Calls, SMS, email, appointments, property changes

// MARK: - Model

public struct LeadActivityEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// "call" | "sms" | "email" | "appointment" | "status_change" | "note"
    public let kind: String
    public let title: String?
    public let body: String?
    /// ISO-8601 timestamp
    public let occurredAt: String
    public let performedBy: String?

    public init(id: Int64, kind: String, title: String? = nil, body: String? = nil,
                occurredAt: String, performedBy: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.occurredAt = occurredAt
        self.performedBy = performedBy
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case occurredAt   = "occurred_at"
        case performedBy  = "performed_by"
    }
}

// MARK: - Networking

extension APIClient {
    /// `GET /api/v1/leads/:id/activity` — chronological activity list.
    public func leadActivity(id: Int64, pageSize: Int = 100) async throws -> [LeadActivityEntry] {
        let items = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        return try await get("/api/v1/leads/\(id)/activity", query: items, as: [LeadActivityEntry].self)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class LeadActivityViewModel {
    public private(set) var entries: [LeadActivityEntry] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let leadId: Int64

    public init(api: APIClient, leadId: Int64) {
        self.api = api
        self.leadId = leadId
    }

    public func load() async {
        if entries.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            entries = try await api.leadActivity(id: leadId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

#if canImport(UIKit)
import UIKit

public struct LeadActivityTimelineView: View {
    @State private var vm: LeadActivityViewModel

    public init(api: APIClient, leadId: Int64) {
        _vm = State(wrappedValue: LeadActivityViewModel(api: api, leadId: leadId))
    }

    public var body: some View {
        Group {
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if let err = vm.errorMessage {
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if vm.entries.isEmpty {
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("No activity yet.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                timelineList
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var timelineList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(vm.entries) { entry in
                timelineRow(entry)
                if entry.id != vm.entries.last?.id {
                    Rectangle()
                        .fill(Color.bizarreOutline.opacity(0.3))
                        .frame(width: 2, height: 12)
                        .padding(.leading, 20)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private func timelineRow(_ entry: LeadActivityEntry) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // Colored dot
            ZStack {
                Circle().fill(entryColor(entry).opacity(0.15))
                Image(systemName: entryIcon(entry))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entryColor(entry))
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    Text(entryTitle(entry))
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer(minLength: 0)
                    Text(shortDate(entry.occurredAt))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(3)
                }
                if let by = entry.performedBy, !by.isEmpty {
                    Text("by \(by)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entryTitle(entry)). \(shortDate(entry.occurredAt)). \(entry.body ?? "")")
    }

    private func entryIcon(_ e: LeadActivityEntry) -> String {
        switch e.kind {
        case "call":          return "phone.fill"
        case "sms":           return "message.fill"
        case "email":         return "envelope.fill"
        case "appointment":   return "calendar.badge.clock"
        case "status_change": return "arrow.triangle.2.circlepath"
        case "note":          return "note.text"
        default:              return "clock"
        }
    }

    private func entryColor(_ e: LeadActivityEntry) -> Color {
        switch e.kind {
        case "call":          return .bizarreOrange
        case "sms":           return .bizarreTeal
        case "email":         return .bizarreOrange
        case "appointment":   return .bizarreSuccess
        case "status_change": return .bizarreWarning
        default:              return .bizarreOnSurfaceMuted
        }
    }

    private func entryTitle(_ e: LeadActivityEntry) -> String {
        if let t = e.title, !t.isEmpty { return t }
        switch e.kind {
        case "call":          return "Call logged"
        case "sms":           return "SMS sent"
        case "email":         return "Email sent"
        case "appointment":   return "Appointment"
        case "status_change": return "Status changed"
        case "note":          return "Note added"
        default:              return e.kind.capitalized
        }
    }

    private func shortDate(_ iso: String) -> String {
        let trimmed = String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
        return trimmed
    }
}
#endif
