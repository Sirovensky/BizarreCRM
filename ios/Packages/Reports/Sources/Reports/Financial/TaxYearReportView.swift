#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - TaxYearReportViewModel

@MainActor
@Observable
final class TaxYearReportViewModel {

    enum LoadState: Sendable {
        case idle, loading, loaded(TaxYearData), failed(String)
    }

    private(set) var loadState: LoadState = .idle
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    private(set) var exportCSV: String?

    @ObservationIgnored private let api: APIClient

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()

    init(api: APIClient) { self.api = api }

    func load() async {
        loadState = .loading
        do {
            let pnlResp = try await api.getFinanceTaxYear(year: selectedYear)
            // Build monthly revenue from full year range
            let months = (1...12).map { month -> (month: String, amountCents: Int) in
                let comps = DateComponents(year: selectedYear, month: month)
                let date = Calendar.current.date(from: comps) ?? Date.distantPast
                return (month: Self.monthFormatter.string(from: date), amountCents: 0)
            }
            let data = TaxYearData(
                year: selectedYear,
                revenueByMonth: months,
                salesTaxCollectedCents: 0,   // Requires separate endpoint
                expensesByCategory: [],
                totalCOGSCents: pnlResp.cogsCents
            )
            loadState = .loaded(data)
        } catch {
            AppLog.ui.error("TaxYear load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    func buildExportCSV() {
        guard case .loaded(let data) = loadState else { return }
        exportCSV = FinancialExportService.exportTaxYearCSV(data: data)
    }
}

// MARK: - TaxYearReportView

public struct TaxYearReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TaxYearReportViewModel
    @State private var showExporter: Bool = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: TaxYearReportViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                contentBody
            }
            .navigationTitle("Tax Year Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.buildExportCSV()
                        showExporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityLabel("Export CSV")
                    }
                    .disabled({
                        if case .loaded = vm.loadState { return false }
                        return true
                    }())
                    .keyboardShortcut("e", modifiers: .command)
                }
            }
            .task { await vm.load() }
            .onChange(of: vm.selectedYear) { _, _ in Task { await vm.load() } }
            .sheet(isPresented: $showExporter) {
                if let csv = vm.exportCSV {
                    ShareSheet(items: [csv as Any])
                }
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch vm.loadState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            errorView(msg)
        case .loaded(let data):
            reportContent(data)
        }
    }

    private func reportContent(_ data: TaxYearData) -> some View {
        ScrollView {
            LazyVStack(spacing: BrandSpacing.md) {
                yearPickerSection
                revenueByMonthSection(data)
                totalsSection(data)
            }
            .padding(BrandSpacing.md)
        }
    }

    // MARK: Year Picker

    private var yearPickerSection: some View {
        HStack {
            Text("Year:")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Stepper("\(vm.selectedYear)", value: $vm.selectedYear, in: 2020...2030)
                .font(.brandBodyLarge())
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Revenue chart

    private func revenueByMonthSection(_ data: TaxYearData) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Revenue by Month — \(data.year)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if data.revenueByMonth.allSatisfy({ $0.amountCents == 0 }) {
                Text("No revenue data for \(data.year).")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(height: 160)
            } else {
                Chart {
                    ForEach(Array(data.revenueByMonth.enumerated()), id: \.offset) { _, point in
                        BarMark(
                            x: .value("Month", point.month),
                            y: .value("Revenue", Double(point.amountCents) / 100.0)
                        )
                        .foregroundStyle(.bizarreOrange)
                    }
                }
                .frame(height: 180)
                // TODO: wrap revenueChartDescriptor(data) in AXChartDescriptorRepresentable
                //       before re-enabling. SwiftUI Charts API requires the wrapper type.
                .accessibilityLabel("Monthly revenue chart, \(data.revenueByMonth.count) months")
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func revenueChartDescriptor(_ data: TaxYearData) -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Month",
            categoryOrder: data.revenueByMonth.map(\.month)
        )
        let yAxis = AXNumericDataAxisDescriptor(title: "Revenue ($)", range: 0...1, gridlinePositions: []) { _ in "" }
        let series = AXDataSeriesDescriptor(
            name: "Monthly Revenue",
            isContinuous: false,
            dataPoints: data.revenueByMonth.map {
                AXDataPoint(x: $0.month, y: Double($0.amountCents) / 100.0)
            }
        )
        return AXChartDescriptor(title: "Revenue by Month \(data.year)", summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }

    // MARK: Totals

    private func totalsSection(_ data: TaxYearData) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Year-End Totals")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            HStack {
                Text("Sales Tax Collected")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(data.salesTaxCollectedCents.financialString)
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOrange)
            }
            HStack {
                Text("Total COGS")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(data.totalCOGSCents.financialString)
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreWarning)
            }
            if !data.expensesByCategory.isEmpty {
                Divider()
                Text("Expenses by Category")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                ForEach(data.expensesByCategory, id: \.category) { item in
                    HStack {
                        Text(item.category)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(item.amountCents.financialString)
                            .font(.brandBodyMedium())
                            .monospacedDigit()
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load tax year data")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ShareSheet shim

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Cents formatter

private extension Int {
    var financialString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(self) / 100.0)) ?? "$0.00"
    }
}
#endif
