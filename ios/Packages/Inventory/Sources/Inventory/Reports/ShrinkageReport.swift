#if canImport(UIKit)
import SwiftUI
import Charts
import DesignSystem
import Networking
import Core

// MARK: - §6.8 Shrinkage Report

// MARK: Models

public struct ShrinkagePoint: Identifiable, Sendable, Decodable {
    public let id: UUID = UUID()
    public let period: String          // e.g. "2026-04"
    public let expectedQty: Int
    public let actualQty: Int
    public let reason: ShrinkageReason
    public let costCents: Int

    public var variance: Int { actualQty - expectedQty }
    public var isLoss: Bool { variance < 0 }
    public var costFormatted: String {
        let dollars = Double(abs(costCents)) / 100.0
        return String(format: "$%.2f", dollars)
    }

    enum CodingKeys: String, CodingKey {
        case period, reason
        case expectedQty = "expected_qty"
        case actualQty = "actual_qty"
        case costCents = "cost_cents"
    }
}

public enum ShrinkageReason: String, CaseIterable, Sendable, Decodable, Identifiable {
    case theft, damage, expiry, adminError = "admin_error", other
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .theft: return "Theft"
        case .damage: return "Damage"
        case .expiry: return "Expiry"
        case .adminError: return "Admin Error"
        case .other: return "Other"
        }
    }
    public var color: Color {
        switch self {
        case .theft: return .bizarreError
        case .damage: return .bizarreWarning
        case .expiry: return .bizarrePrimary
        case .adminError: return .bizarreTextSecondary
        case .other: return Color.secondary
        }
    }
}

public struct ShrinkageSummary: Sendable {
    public let totalUnitsLost: Int
    public let totalCostCents: Int
    public let shrinkagePct: Double
    public var costFormatted: String {
        String(format: "$%.2f", Double(totalCostCents) / 100.0)
    }
}

// MARK: Pure Calculator

public enum ShrinkageCalculator {
    public static func summary(from points: [ShrinkagePoint]) -> ShrinkageSummary {
        let unitsLost = points.filter(\.isLoss).reduce(0) { $0 + abs($1.variance) }
        let costCents = points.filter(\.isLoss).reduce(0) { $0 + $1.costCents }
        let totalExpected = points.reduce(0) { $0 + $1.expectedQty }
        let shrinkagePct = totalExpected > 0
            ? Double(unitsLost) / Double(totalExpected) * 100.0
            : 0.0
        return ShrinkageSummary(
            totalUnitsLost: unitsLost,
            totalCostCents: costCents,
            shrinkagePct: shrinkagePct
        )
    }

    public static func byReason(from points: [ShrinkagePoint]) -> [(ShrinkageReason, Int)] {
        var counts: [ShrinkageReason: Int] = [:]
        for p in points where p.isLoss {
            counts[p.reason, default: 0] += abs(p.variance)
        }
        return ShrinkageReason.allCases.compactMap { reason in
            let qty = counts[reason] ?? 0
            return qty > 0 ? (reason, qty) : nil
        }
    }
}

// MARK: ViewModel

@MainActor
@Observable
public final class ShrinkageReportViewModel {
    public private(set) var points: [ShrinkagePoint] = []
    public private(set) var summary: ShrinkageSummary = ShrinkageSummary(
        totalUnitsLost: 0, totalCostCents: 0, shrinkagePct: 0
    )
    public private(set) var byReason: [(ShrinkageReason, Int)] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var periodMonths: Int = 3

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            points = try await api.shrinkageReport(months: periodMonths)
            summary = ShrinkageCalculator.summary(from: points)
            byReason = ShrinkageCalculator.byReason(from: points)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: View

public struct ShrinkageReportView: View {
    @State private var vm: ShrinkageReportViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: ShrinkageReportViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.points.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                errorState(message: err)
            } else {
                reportContent
            }
        }
        .navigationTitle("Shrinkage Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { periodPicker }
        .task { await vm.load() }
    }

    // MARK: Report Content

    private var reportContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                kpiTiles
                trendChart
                byReasonChart
            }
            .padding()
        }
    }

    // MARK: KPI Tiles

    private var kpiTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            kpiTile("Units Lost", value: "\(vm.summary.totalUnitsLost)", color: .bizarreError)
            kpiTile("Cost", value: vm.summary.costFormatted, color: .bizarreWarning)
            kpiTile("Shrinkage %", value: String(format: "%.1f%%", vm.summary.shrinkagePct), color: .bizarrePrimary)
        }
    }

    private func kpiTile(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.bizarreTitle2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.bizarreCaption)
                .foregroundStyle(Color.bizarreTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.bizarreSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Trend Chart

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variance Trend")
                .font(.bizarreHeadline)
                .padding(.horizontal, 4)

            if vm.points.isEmpty {
                Text("No data for this period.")
                    .font(.bizarreBody)
                    .foregroundStyle(Color.bizarreTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart(vm.points) { point in
                    BarMark(
                        x: .value("Period", point.period),
                        y: .value("Variance", point.variance)
                    )
                    .foregroundStyle(point.isLoss ? Color.bizarreError : Color.bizarrePrimary)
                }
                .chartYAxisLabel("Variance (units)")
                .frame(height: 180)
                .accessibilityLabel("Shrinkage variance bar chart by period")
            }
        }
        .padding()
        .background(Color.bizarreSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: By Reason Chart

    private var byReasonChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Loss by Reason")
                .font(.bizarreHeadline)
                .padding(.horizontal, 4)
            if vm.byReason.isEmpty {
                Text("No losses recorded.")
                    .font(.bizarreBody)
                    .foregroundStyle(Color.bizarreTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart {
                    ForEach(vm.byReason, id: \.0) { reason, qty in
                        BarMark(
                            x: .value("Reason", reason.label),
                            y: .value("Units", qty)
                        )
                        .foregroundStyle(reason.color)
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Units lost by reason bar chart")
            }
        }
        .padding()
        .background(Color.bizarreSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Error

    @ViewBuilder
    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.bizarreError)
            Text("Can't load shrinkage report")
                .font(.bizarreHeadline)
            Text(message)
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: Period Picker

    @ToolbarContentBuilder
    private var periodPicker: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach([1, 3, 6, 12], id: \.self) { months in
                    Button("\(months) month\(months == 1 ? "" : "s")") {
                        vm.periodMonths = months
                        Task { await vm.load() }
                    }
                }
            } label: {
                Label("Period: \(vm.periodMonths)mo", systemImage: "calendar")
            }
            .accessibilityLabel("Select report period")
        }
    }
}

// MARK: - APIClient extension (§6.8 Shrinkage)

extension APIClient {
    func shrinkageReport(months: Int) async throws -> [ShrinkagePoint] {
        try await get("/api/v1/inventory/reports/shrinkage?months=\(months)", as: [ShrinkagePoint].self)
    }
}
#endif
