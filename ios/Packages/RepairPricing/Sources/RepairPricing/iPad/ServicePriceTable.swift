import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §22 Service Price Table (iPad)

/// Sortable SwiftUI `Table` showing a device template's repair services.
///
/// Columns:
///   1. Service Name  (default sort: ascending)
///   2. Labor         (labor price in cents, formatted as currency)
///   3. Parts         (part SKU reference; shows "—" when absent)
///   4. Total         (labor + 0 parts; real parts cost from inventory TBD)
///
/// Sorting is entirely local — no network call on column tap. Pull-to-refresh
/// triggers a detail reload from the API.
///
/// This view loads the full device template detail (which includes the enriched
/// services list) when `template.services` is nil. Once loaded the data is
/// cached in local `@State`.
@MainActor
public struct ServicePriceTable: View {

    // MARK: - Init

    private let initialTemplate: DeviceTemplate
    private let api: APIClient

    public init(template: DeviceTemplate, api: APIClient) {
        self.initialTemplate = template
        self.api = api
    }

    // MARK: - State

    @State private var services: [ServicePriceRow] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    // Sort state
    @State private var sortOrder: [KeyPathComparator<ServicePriceRow>] = [
        KeyPathComparator(\ServicePriceRow.serviceName, order: .forward)
    ]

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading services")
            } else if let err = errorMessage {
                errorView(message: err)
            } else if services.isEmpty {
                emptyView
            } else {
                serviceTable
            }
        }
        .navigationTitle(initialTemplate.model ?? initialTemplate.name)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .toolbar {
            headerStats
        }
        .task { await loadServices() }
        .refreshable { await loadServices(force: true) }
    }

    // MARK: - Table

    private var serviceTable: some View {
        Table(sortedServices, sortOrder: $sortOrder) {
            // Column 1: Service Name
            TableColumn("Service", value: \ServicePriceRow.serviceName) { row in
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(row.serviceName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    if let sku = row.partSku, !sku.isEmpty {
                        Text("SKU: \(sku)")
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                            .accessibilityLabel("Part number \(sku)")
                    }
                    if let mins = row.estimatedMinutes {
                        Text("\(mins) min")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
            .width(min: 180, ideal: 260)

            // Column 2: Labor
            TableColumn("Labor", value: \ServicePriceRow.laborCents) { row in
                Text(formatCents(row.laborCents))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Labor \(formatCents(row.laborCents))")
            }
            .width(min: 80, ideal: 100, max: 130)

            // Column 3: Parts
            TableColumn("Parts", value: \ServicePriceRow.partsCents) { row in
                Text(row.partsCents > 0 ? formatCents(row.partsCents) : "—")
                    .font(.brandBodyMedium())
                    .foregroundStyle(row.partsCents > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Parts \(row.partsCents > 0 ? formatCents(row.partsCents) : "not set")")
            }
            .width(min: 80, ideal: 100, max: 130)

            // Column 4: Total
            TableColumn("Total", value: \ServicePriceRow.totalCents) { row in
                Text(formatCents(row.totalCents))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Total \(formatCents(row.totalCents))")
            }
            .width(min: 80, ideal: 110, max: 140)
        }
        .tableStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Sorted data

    private var sortedServices: [ServicePriceRow] {
        services.sorted(using: sortOrder)
    }

    // MARK: - Toolbar stats

    @ToolbarContentBuilder
    private var headerStats: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            if !services.isEmpty {
                let totalRevenue = services.map(\.totalCents).reduce(0, +)
                BrandGlassBadge(
                    "\(services.count) services · avg \(formatCents(totalRevenue / services.count))",
                    variant: .regular
                )
                .accessibilityLabel("\(services.count) services, average price \(formatCents(totalRevenue / services.count))")
            }
        }
    }

    // MARK: - Empty / error states

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Services")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("This template has no repair services defined yet.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load services")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await loadServices(force: true) } }
                .buttonStyle(BrandGlassButtonStyle())
                .tint(.bizarreOrange)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data loading

    private func loadServices(force: Bool = false) async {
        // Skip if we already have services and this isn't a forced refresh.
        if !force, !services.isEmpty { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let detail: DeviceTemplate
            if !force, let svcList = initialTemplate.services {
                // Services already embedded in the template from the list endpoint.
                detail = initialTemplate
                services = svcList.map(ServicePriceRow.init)
                return
            }
            detail = try await api.getDeviceTemplate(id: initialTemplate.id)
            services = (detail.services ?? []).map(ServicePriceRow.init)
        } catch {
            AppLog.ui.error("ServicePriceTable load: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row model

/// View-model row for `Table` — provides `KeyPath` sortable properties.
public struct ServicePriceRow: Identifiable, Sendable {
    public let id: Int64
    public let serviceName: String
    /// Labor price in cents (= `defaultPriceCents` from the service DTO).
    public let laborCents: Int
    /// Parts cost in cents (0 if no SKU / no linked inventory price).
    public let partsCents: Int
    /// Total = labor + parts.
    public var totalCents: Int { laborCents + partsCents }
    public let partSku: String?
    public let estimatedMinutes: Int?

    public init(_ service: RepairService) {
        self.id = service.id
        self.serviceName = service.serviceName
        self.laborCents = service.defaultPriceCents
        // Parts cost is not returned by the current API; default to 0 until
        // the inventory-linked pricing endpoint is wired.
        self.partsCents = 0
        self.partSku = service.partSku
        self.estimatedMinutes = service.estimatedMinutes
    }

    /// Memberwise init used in tests.
    public init(
        id: Int64,
        serviceName: String,
        laborCents: Int,
        partsCents: Int = 0,
        partSku: String? = nil,
        estimatedMinutes: Int? = nil
    ) {
        self.id = id
        self.serviceName = serviceName
        self.laborCents = laborCents
        self.partsCents = partsCents
        self.partSku = partSku
        self.estimatedMinutes = estimatedMinutes
    }
}

// MARK: - Currency formatter (local, avoids cross-package dep on Pos.CartMath)

private func formatCents(_ cents: Int) -> String {
    let dollars = Double(cents) / 100.0
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "USD"
    return fmt.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
}
