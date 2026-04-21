import SwiftUI
import Core
import DesignSystem
import Networking

/// §43.1 Device detail — shows header + services list for a single template.
///
/// Services are loaded from the full template detail endpoint so we always
/// have the enriched parts + pricing, even when the catalog list was loaded
/// without services.
@MainActor
public struct RepairPricingDeviceDetailView: View {
    private let initialTemplate: DeviceTemplate
    private let api: APIClient

    @State private var template: DeviceTemplate
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(template: DeviceTemplate, api: APIClient) {
        self.initialTemplate = template
        self.api = api
        _template = State(wrappedValue: template)
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading device details")
            } else if let err = errorMessage {
                errorView(message: err)
            } else {
                content
            }
        }
        .navigationTitle(template.model ?? template.name)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadDetail() }
    }

    // MARK: - Content

    private var content: some View {
        List {
            // Header section
            Section {
                deviceHeader
            }
            .listRowBackground(Color.bizarreSurface1)
            .listRowInsets(EdgeInsets())

            // Conditions
            if !template.conditions.isEmpty {
                Section("Conditions") {
                    conditionChips
                }
                .listRowBackground(Color.bizarreSurface1)
            }

            // Services
            if let services = template.services, !services.isEmpty {
                Section("Repair Services") {
                    ForEach(services) { service in
                        ServiceRow(service: service)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Adjust") { /* §43.3 price override — coming later */ }
                                    .tint(.bizarreOrange)
                            }
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
            } else {
                Section("Repair Services") {
                    Text("No services defined for this device.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("No services available")
                }
                .listRowBackground(Color.bizarreSurface1)
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Header

    private var deviceHeader: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            thumbnailView
                .frame(width: 64, height: 64)
                .foregroundStyle(.bizarreOrange)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(template.name)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                if let family = template.family {
                    Text(family)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let price = template.defaultPriceCents {
                    Text(CartMath.formatCents(price))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Default price \(CartMath.formatCents(price))")
                }
                if template.warrantyDays > 0 {
                    Text("\(template.warrantyDays)-day warranty")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.base)
        .accessibilityElement(children: .combine)
    }

    private var conditionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(template.conditions, id: \.self) { condition in
                    Text(condition)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.vertical, BrandSpacing.xs)
                        .foregroundStyle(.bizarreOnSurface)
                        .background(Color.bizarreSurface2, in: Capsule())
                        .accessibilityLabel("Condition: \(condition)")
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .padding(.horizontal, BrandSpacing.base)
        }
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let urlString = template.thumbnailUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure, .empty:
                    fallbackIcon
                @unknown default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: deviceSystemImageForDetail(family: template.family))
            .resizable()
            .scaledToFit()
    }

    // MARK: - Error state

    @ViewBuilder
    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load details")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await loadDetail() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func loadDetail() async {
        // Skip if we already have services populated (e.g. from a cached fetch)
        guard template.services == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let detail = try await api.getDeviceTemplate(id: template.id)
            template = detail
        } catch {
            AppLog.ui.error("DeviceTemplate detail load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Service row

private struct ServiceRow: View {
    let service: RepairService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(service.serviceName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let sku = service.partSku, !sku.isEmpty {
                    Text("SKU: \(sku)")
                        .font(.brandMono(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                        .accessibilityLabel("Part number \(sku)")
                }
                if let mins = service.estimatedMinutes {
                    Text("\(mins) min est.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("Estimated \(mins) minutes")
                }
            }
            Spacer()
            Text(CartMath.formatCents(service.defaultPriceCents))
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOrange)
                .monospacedDigit()
                .accessibilityLabel("Price \(CartMath.formatCents(service.defaultPriceCents))")
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Helpers

private func deviceSystemImageForDetail(family: String?) -> String {
    switch family?.lowercased() {
    case "apple":   return "iphone.gen3"
    case "samsung": return "iphone.gen2"
    case "google":  return "iphone.gen1"
    case "tablet":  return "ipad"
    default:        return "iphone"
    }
}

// MARK: - CartMath shim

/// Lightweight price formatter — mirrors the naming convention used by Pos.CartMath
/// but lives in RepairPricing so we don't create a cross-package dep on Pos.
enum CartMath {
    static func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        return fmt.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}
