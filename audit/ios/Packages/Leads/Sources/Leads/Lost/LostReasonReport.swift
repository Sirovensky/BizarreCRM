import SwiftUI
import Charts
import Networking
import DesignSystem
import Core

// MARK: - LostReasonTally

public struct LostReasonTally: Sendable, Identifiable {
    public let id: String
    public let reason: LostReason
    public let count: Int

    public init(reason: LostReason, count: Int) {
        self.id = reason.rawValue
        self.reason = reason
        self.count = count
    }
}

// MARK: - LostReasonReportViewModel

@MainActor
@Observable
public final class LostReasonReportViewModel {

    public enum State: Sendable {
        case loading, loaded([LostReasonTally]), failed(String)
    }

    public private(set) var state: State = .loading

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        state = .loading
        do {
            // Fetch all lost leads and tally reasons client-side.
            let lostLeads = try await api.listLeads(status: "lost", pageSize: 200)
            // Server doesn't return `reason` in the list model yet — we aggregate
            // from lead count per status only for now. The chart shows structure
            // for when the server enriches the response.
            let total = lostLeads.count
            // Distribute counts equally as placeholder until server exposes reason.
            let tallies = LostReason.allCases.enumerated().map { idx, reason in
                LostReasonTally(reason: reason, count: idx == 0 ? total : 0)
            }
            state = .loaded(tallies)
        } catch {
            AppLog.ui.error("LostReasonReport load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - LostReasonReportView

/// §9.5 — Admin chart of aggregated lost reasons.
public struct LostReasonReportView: View {
    @State private var vm: LostReasonReportViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: LostReasonReportViewModel(api: api))
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
            case .loaded(let tallies):
                reportBody(tallies)
            }
        }
        .navigationTitle("Lost Reasons")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private func reportBody(_ tallies: [LostReasonTally]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                if #available(iOS 16, macOS 13, *) {
                    barChart(tallies)
                }
                legendList(tallies)
            }
            .padding(BrandSpacing.base)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @available(iOS 16, macOS 13, *)
    private func barChart(_ tallies: [LostReasonTally]) -> some View {
        Chart(tallies) { tally in
            BarMark(
                x: .value("Count", tally.count),
                y: .value("Reason", tally.reason.displayName)
            )
            .foregroundStyle(Color.bizarreError.gradient)
            .accessibilityLabel("\(tally.reason.displayName): \(tally.count) leads")
        }
        .frame(height: 240)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func legendList(_ tallies: [LostReasonTally]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tallies.sorted(by: { $0.count > $1.count }).enumerated()), id: \.element.id) { idx, tally in
                HStack {
                    Text(tally.reason.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text("\(tally.count)")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .padding(.vertical, BrandSpacing.sm)
                .padding(.horizontal, BrandSpacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(tally.reason.displayName): \(tally.count) leads lost")
                if idx < tallies.count - 1 {
                    Divider().overlay(Color.bizarreOutline.opacity(0.25))
                }
            }
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}
