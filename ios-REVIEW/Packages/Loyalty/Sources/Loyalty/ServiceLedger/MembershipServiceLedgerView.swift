import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §38.5 Service ledger per period
// "Included services remaining: 3 of 5"; decrement at POS redemption

// MARK: - Models

public struct MembershipServiceLedger: Decodable, Sendable {
    public let membershipId: String
    public let planName: String
    public let periodStart: String
    public let periodEnd: String
    /// Total included services in this plan period.
    public let includedCount: Int
    /// How many have been used so far.
    public let usedCount: Int
    /// Individual service usage entries
    public let entries: [ServiceLedgerEntry]

    public var remainingCount: Int { max(0, includedCount - usedCount) }

    public init(membershipId: String, planName: String, periodStart: String, periodEnd: String,
                includedCount: Int, usedCount: Int, entries: [ServiceLedgerEntry] = []) {
        self.membershipId = membershipId
        self.planName = planName
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.includedCount = includedCount
        self.usedCount = usedCount
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case entries
        case membershipId  = "membership_id"
        case planName      = "plan_name"
        case periodStart   = "period_start"
        case periodEnd     = "period_end"
        case includedCount = "included_count"
        case usedCount     = "used_count"
    }
}

public struct ServiceLedgerEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let serviceDescription: String
    public let usedAt: String
    public let ticketId: Int64?

    public init(id: Int64, serviceDescription: String, usedAt: String, ticketId: Int64? = nil) {
        self.id = id
        self.serviceDescription = serviceDescription
        self.usedAt = usedAt
        self.ticketId = ticketId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case serviceDescription = "service_description"
        case usedAt             = "used_at"
        case ticketId           = "ticket_id"
    }
}

// MARK: - Networking

extension APIClient {
    /// `GET /api/v1/memberships/:id/service-ledger` — per-period service usage.
    public func membershipServiceLedger(membershipId: String) async throws -> MembershipServiceLedger {
        try await get("/api/v1/memberships/\(membershipId)/service-ledger", as: MembershipServiceLedger.self)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class MembershipServiceLedgerViewModel {
    public private(set) var ledger: MembershipServiceLedger?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let membershipId: String

    public init(api: APIClient, membershipId: String) {
        self.api = api
        self.membershipId = membershipId
    }

    public func load() async {
        if ledger == nil { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            ledger = try await api.membershipServiceLedger(membershipId: membershipId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

#if canImport(UIKit)

public struct MembershipServiceLedgerView: View {
    @State private var vm: MembershipServiceLedgerViewModel

    public init(api: APIClient, membershipId: String) {
        _vm = State(wrappedValue: MembershipServiceLedgerViewModel(api: api, membershipId: membershipId))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let ledger = vm.ledger {
                    ledgerContent(ledger)
                }
            }
        }
        .navigationTitle("Service Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private func ledgerContent(_ ledger: MembershipServiceLedger) -> some View {
        List {
            Section {
                // Header — remaining / included
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    HStack {
                        Text(ledger.planName)
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer(minLength: 0)
                        Text("\(ledger.remainingCount) of \(ledger.includedCount) remaining")
                            .font(.brandTitleSmall())
                            .foregroundStyle(ledger.remainingCount > 0 ? .bizarreSuccess : .bizarreError)
                            .monospacedDigit()
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.bizarreSurface2).frame(height: 8)
                            Capsule()
                                .fill(ledger.remainingCount > 0 ? Color.bizarreSuccess : Color.bizarreError)
                                .frame(
                                    width: geo.size.width * CGFloat(ledger.usedCount) / CGFloat(max(1, ledger.includedCount)),
                                    height: 8
                                )
                        }
                    }
                    .frame(height: 8)
                    .accessibilityLabel("Used \(ledger.usedCount) of \(ledger.includedCount) included services")

                    HStack {
                        Text("Period: \(shortDate(ledger.periodStart)) – \(shortDate(ledger.periodEnd))")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
                .listRowBackground(Color.bizarreSurface1)
            }

            if ledger.entries.isEmpty {
                Section("Usage") {
                    Text("No services used this period.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .listRowBackground(Color.bizarreSurface1)
                }
            } else {
                Section("Usage (\(ledger.usedCount))") {
                    ForEach(ledger.entries) { entry in
                        ledgerRow(entry)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func ledgerRow(_ entry: ServiceLedgerEntry) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreSuccess)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.serviceDescription)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.xs) {
                    Text(shortDate(entry.usedAt))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if let ticketId = entry.ticketId {
                        Text("Ticket #\(ticketId)")
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, BrandSpacing.xs)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.serviceDescription), used \(shortDate(entry.usedAt))\(entry.ticketId.map { ", ticket \($0)" } ?? "")")
    }

    private func shortDate(_ iso: String) -> String {
        String(iso.prefix(10))
    }
}

#endif
