#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - §41.8 Analytics dashboard

/// Admin view: conversion funnel + per-link breakdown.
/// iPhone: NavigationStack list with funnel chart header.
/// iPad: NavigationSplitView — sidebar funnel, detail per-link table.
public struct PaymentLinksDashboardView: View {
    @State private var vm: PaymentLinksDashboardViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: PaymentLinksDashboardViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Payment links analytics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh analytics")
                .brandGlass(.regular, in: Circle(), interactive: true)
            }
        }
        .task { await vm.load() }
    }

    // MARK: - iPhone

    private var iPhoneLayout: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.analytics == nil {
                ProgressView()
            } else {
                List {
                    Section {
                        funnelChart
                            .frame(height: 220)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                    aggregateSummarySection
                    perLinkSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - iPad

    private var iPadLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                List {
                    Section {
                        funnelChart
                            .frame(height: 260)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                    aggregateSummarySection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Funnel")
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                List {
                    perLinkSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Per link")
        }
    }

    // MARK: - Funnel chart

    private var funnelChart: some View {
        Group {
            if let agg = vm.analytics?.aggregate {
                Chart {
                    ForEach(vm.funnelStages(from: agg), id: \.label) { stage in
                        BarMark(
                            x: .value("Stage", stage.label),
                            y: .value("Count", stage.count)
                        )
                        .foregroundStyle(Color.bizarreOrange.gradient)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text("\(stage.count)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurface)
                        }
                    }
                }
                .chartYAxis(.hidden)
                .accessibilityLabel("Payment link conversion funnel")
            } else {
                ContentUnavailableView("No analytics data", systemImage: "chart.bar")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var aggregateSummarySection: some View {
        if let agg = vm.analytics?.aggregate {
            Section("Overall performance") {
                LabeledContent("Total links", value: "\(agg.totalLinks)")
                LabeledContent("Sent", value: "\(agg.totalSent)")
                LabeledContent("Opened", value: "\(agg.totalOpened)")
                LabeledContent("Paid", value: "\(agg.totalPaid)")
                LabeledContent("Revenue", value: CartMath.formatCents(agg.totalRevenueCents))
                    .font(.brandTitleSmall())
                LabeledContent(
                    "Conversion",
                    value: String(format: "%.1f%%", agg.overallConversionRate * 100)
                )
                .foregroundStyle(agg.overallConversionRate > 0.3 ? .green : .orange)
            }
            .listRowBackground(Color.bizarreSurface1)
        }
    }

    @ViewBuilder
    private var perLinkSection: some View {
        if let rows = vm.analytics?.perLink, !rows.isEmpty {
            Section("Per link") {
                ForEach(rows) { row in
                    AnalyticsLinkRow(row: row)
                        .listRowBackground(Color.bizarreSurface1)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "Link \(row.id): \(row.paid) paid of \(row.opened) opened"
                        )
                }
            }
        }
    }
}

// MARK: - Per-link row

struct AnalyticsLinkRow: View {
    let row: PaymentLinkAnalytics

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Link #\(row.id)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(row.opened) opened · \(row.clicked) clicked")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.paid) paid")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.green)
                Text(String(format: "%.0f%%", row.openToPaidRate * 100))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PaymentLinksDashboardViewModel {
    public private(set) var analytics: PaymentLinksAnalyticsResponse?
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            analytics = try await api.getPaymentLinksAnalytics()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load analytics."
        }
    }

    public struct FunnelStage: Sendable {
        public let label: String
        public let count: Int
    }

    public func funnelStages(from agg: PaymentLinksAggregate) -> [FunnelStage] {
        [
            FunnelStage(label: "Sent",    count: agg.totalSent),
            FunnelStage(label: "Opened",  count: agg.totalOpened),
            FunnelStage(label: "Clicked", count: agg.totalClicked),
            FunnelStage(label: "Paid",    count: agg.totalPaid)
        ]
    }
}
#endif
