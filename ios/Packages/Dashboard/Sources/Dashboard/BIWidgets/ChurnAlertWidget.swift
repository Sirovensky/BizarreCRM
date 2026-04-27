import SwiftUI
import Observation
import DesignSystem

// MARK: - ChurnAlertWidget
//
// §3.2 Churn Alert — at-risk customer count; tap → Customers filtered `churn_risk`.
// Source: GET /api/v1/reports/churn (reports.routes.ts line 2538)

// MARK: - ViewModel

@MainActor
@Observable
public final class ChurnAlertViewModel {
    public let title = "Churn Alert"
    public private(set) var state: BIWidgetState<ChurnPayload> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchChurn()
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

public struct ChurnAlertWidget: View, BIWidgetView {
    public let widgetTitle = "Churn Alert"
    @State private var vm: ChurnAlertViewModel
    /// Called when the user taps the card — should navigate to Customers filtered by `churn_risk`.
    public var onTapChurnList: (() -> Void)?

    public init(vm: ChurnAlertViewModel, onTapChurnList: (() -> Void)? = nil) {
        _vm = State(wrappedValue: vm)
        self.onTapChurnList = onTapChurnList
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "person.fill.xmark") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let data):
                ChurnAlertContent(data: data, onTapChurnList: onTapChurnList)
            case .failed(let msg):
                BIWidgetErrorState(message: msg) { Task { await vm.reload() } }
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - Content

private struct ChurnAlertContent: View {
    let data: ChurnPayload
    var onTapChurnList: (() -> Void)?

    var body: some View {
        Button {
            onTapChurnList?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // At-risk count
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(data.atRiskCount)")
                            .font(.brandDisplaySmall())
                            .foregroundStyle(data.atRiskCount > 0 ? .bizarreWarning : .bizarreOnSurface)
                            .monospacedDigit()
                        Text("at risk")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Text("Inactive >\(data.thresholdDays) days")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                // Top at-risk customers (up to 3)
                if !data.customers.isEmpty {
                    Divider()
                    VStack(spacing: 6) {
                        ForEach(data.customers.prefix(3)) { customer in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(customer.name)
                                        .font(.brandBodySmall())
                                        .foregroundStyle(.bizarreOnSurface)
                                        .lineLimit(1)
                                    Text("\(customer.daysInactive)d inactive")
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                                Spacer(minLength: 4)
                            }
                        }
                    }
                }

                if data.atRiskCount == 0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreTeal)
                        Text("No customers at risk")
                            .font(.brandBodySmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                } else {
                    HStack {
                        Spacer()
                        Label("View At-Risk Customers", systemImage: "chevron.right")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOrange)
                    }
                }
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Churn alert: \(data.atRiskCount) customers at risk of churning. Tap to view list.")
    }
}
