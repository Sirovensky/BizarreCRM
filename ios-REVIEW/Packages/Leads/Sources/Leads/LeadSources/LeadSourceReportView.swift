import SwiftUI
import Charts
import Networking
import DesignSystem
import Core

// MARK: - LeadSourceReportViewModel

@MainActor
@Observable
public final class LeadSourceReportViewModel {

    public enum State: Sendable {
        case loading, loaded([LeadSourceStats]), failed(String)
    }

    public private(set) var state: State = .loading

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        state = .loading
        do {
            let leads = try await api.listLeads(pageSize: 200)
            let stats = LeadSourceAnalytics.computeStats(from: leads)
            state = .loaded(stats)
        } catch {
            AppLog.ui.error("SourceReport load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - LeadSourceReportView

/// §9.7 — Admin chart: per-source conversion rate + lead count.
public struct LeadSourceReportView: View {
    @State private var vm: LeadSourceReportViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: LeadSourceReportViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            switch vm.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .padding()
            case .loaded(let stats):
                reportBody(stats)
            }
        }
        .navigationTitle("Lead Sources")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private func reportBody(_ stats: [LeadSourceStats]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                if #available(iOS 16, macOS 13, *) {
                    conversionChart(stats)
                }
                statsList(stats)
            }
            .padding(BrandSpacing.base)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @available(iOS 16, macOS 13, *)
    private func conversionChart(_ stats: [LeadSourceStats]) -> some View {
        sourceBarChart(stats)
    }

    @available(iOS 16, macOS 13, *)
    private func sourceBarChart(_ stats: [LeadSourceStats]) -> some View {
        Chart(stats) { s in
            BarMark(
                x: .value("Source", s.source.displayName),
                y: .value("Conversion %", s.conversionRate * 100)
            )
            .foregroundStyle(Color.bizarreOrange.gradient)
            .annotation(position: .top) {
                Text(s.conversionRateLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .chartYAxis { AxisMarks() }
        .frame(height: 220)
        .padding(BrandSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.bizarreSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.bizarreOutline, lineWidth: 0.5)
                .opacity(0.4)
        )
        .accessibilityLabel("Bar chart of lead conversion rates by source")
    }

    private func statsList(_ stats: [LeadSourceStats]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { idx, s in
                HStack(spacing: BrandSpacing.md) {
                    Image(systemName: s.source.iconName)
                        .foregroundStyle(.bizarreOrange)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text(s.source.displayName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("\(s.totalLeads) leads")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                        Text(s.conversionRateLabel)
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                        Text("\(s.convertedLeads) won")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .padding(.vertical, BrandSpacing.sm)
                .padding(.horizontal, BrandSpacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(s.source.displayName): \(s.totalLeads) leads, \(s.conversionRateLabel) converted")
                if idx < stats.count - 1 {
                    Divider().overlay(Color.bizarreOutline.opacity(0.25))
                }
            }
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}
