import SwiftUI
import Observation
import DesignSystem

// MARK: - CashTrappedWidget
//
// §3.2 Cash-Trapped card — overdue receivables sum; tap → Aging report.
// Source: GET /api/v1/reports/cash-trapped (reports.routes.ts line 2381)

// MARK: - ViewModel

@MainActor
@Observable
public final class CashTrappedViewModel {
    public let title = "Cash Trapped"
    public private(set) var state: BIWidgetState<CashTrappedPayload> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchCashTrapped()
            state = .loaded(payload)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func reload() async {
        state = .idle
        await load()
    }
}

// MARK: - View

public struct CashTrappedWidget: View, BIWidgetView {
    public let widgetTitle = "Cash Trapped"
    @State private var vm: CashTrappedViewModel
    /// Called when the user taps the card — should navigate to Aging report.
    public var onTapAgingReport: (() -> Void)?

    public init(vm: CashTrappedViewModel, onTapAgingReport: (() -> Void)? = nil) {
        _vm = State(wrappedValue: vm)
        self.onTapAgingReport = onTapAgingReport
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "dollarsign.arrow.circlepath") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let data):
                CashTrappedContent(data: data, onTapAgingReport: onTapAgingReport)
            case .failed(let msg):
                BIWidgetErrorState(message: msg) { Task { await vm.reload() } }
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - Content

private struct CashTrappedContent: View {
    let data: CashTrappedPayload
    var onTapAgingReport: (() -> Void)?

    private static let moneyFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    private func formatMoney(_ v: Double) -> String {
        Self.moneyFmt.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    var body: some View {
        Button {
            onTapAgingReport?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Big total
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatMoney(data.totalCashTrapped))
                        .font(.brandDisplaySmall())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("\(data.itemCount) overdue invoice\(data.itemCount == 1 ? "" : "s")")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                // Top offenders list (up to 3)
                if !data.topOffenders.isEmpty {
                    Divider()
                    VStack(spacing: 6) {
                        ForEach(data.topOffenders.prefix(3)) { item in
                            HStack {
                                Text(item.name)
                                    .font(.brandBodySmall())
                                    .foregroundStyle(.bizarreOnSurface)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(formatMoney(item.value))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreError)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Label("View Aging Report", systemImage: "chevron.right")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                }
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cash trapped: \(formatMoney(data.totalCashTrapped)) across \(data.itemCount) overdue invoices. Tap to view aging report.")
    }
}
