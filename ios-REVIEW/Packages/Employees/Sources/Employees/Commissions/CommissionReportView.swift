import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - CommissionReportViewModel

@MainActor
@Observable
public final class CommissionReportViewModel {
    public private(set) var payouts: [CommissionPayout] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    public var totalForPeriod: Double {
        payouts.reduce(0) { $0 + $1.amount }
    }

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let employeeId: Int64

    public init(api: APIClient, employeeId: Int64) {
        self.api = api
        self.employeeId = employeeId
    }

    public func load() async {
        if payouts.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            payouts = try await api.fetchCommissionReport(employeeId: employeeId)
        } catch {
            AppLog.ui.error("Commission report load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - CommissionReportView

public struct CommissionReportView: View {
    @State private var vm: CommissionReportViewModel

    public init(api: APIClient, employeeId: Int64) {
        _vm = State(wrappedValue: CommissionReportViewModel(api: api, employeeId: employeeId))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("My Commissions")
        }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("My Commissions")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load commissions")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.payouts.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No commission payouts").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text("Your earned commissions will appear here.")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    totalCard
                    payoutList
                }
                .padding(BrandSpacing.lg)
            }
        }
    }

    // MARK: - Total card

    private var totalCard: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Total this period")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(formatMoney(vm.totalForPeriod))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total commissions this period: \(formatMoney(vm.totalForPeriod))")
    }

    // MARK: - Payout list

    private var payoutList: some View {
        VStack(spacing: BrandSpacing.sm) {
            ForEach(vm.payouts) { payout in
                HStack {
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text(payout.period)
                            .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                        if let paid = payout.paidAt {
                            Text("Paid \(String(paid.prefix(10)))")
                                .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        if let notes = payout.notes, !notes.isEmpty {
                            Text(notes).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(formatMoney(payout.amount))
                        .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
                }
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Period \(payout.period). Amount \(formatMoney(payout.amount)). \(payout.paidAt.map { "Paid \($0.prefix(10))" } ?? "Pending")")
            }
        }
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
