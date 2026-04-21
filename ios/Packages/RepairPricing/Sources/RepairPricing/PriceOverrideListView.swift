import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §43.3 Price Override List View (Admin)

/// Admin view: Settings → Repair Pricing → Overrides.
/// Lists all price overrides with delete swipe action.
@MainActor
public struct PriceOverrideListView: View {
    @State private var vm: PriceOverrideListViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: PriceOverrideListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                padLayout
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: - iPhone

    private var phoneLayout: some View {
        NavigationStack {
            content
                .navigationTitle("Price Overrides")
                #if canImport(UIKit)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                #endif
        }
    }

    // MARK: - iPad

    private var padLayout: some View {
        content
            .navigationTitle("Price Overrides")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.large)
            #endif
    }

    // MARK: - Shared content

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading overrides")
            } else if let err = vm.errorMessage {
                errorView(message: err)
            } else if vm.overrides.isEmpty {
                emptyView
            } else {
                overrideList
            }
        }
    }

    private var overrideList: some View {
        List {
            ForEach(vm.overrides) { item in
                OverrideRow(override: item)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await vm.delete(override: item) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "tag.slash")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Price Overrides")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Override service prices for specific tenants or VIP customers.")
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
            Text("Couldn't load overrides")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Override Row

private struct OverrideRow: View {
    let override: PriceOverride

    private var formattedPrice: String {
        let dollars = Double(override.priceCents) / 100.0
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        return fmt.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text("Service \(override.serviceId)")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Service ID \(override.serviceId)")
                Spacer()
                Text(formattedPrice)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
                    .accessibilityLabel("Override price \(formattedPrice)")
            }
            HStack(spacing: BrandSpacing.sm) {
                scopeBadge
                if let cid = override.customerId {
                    Text("Customer \(cid)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                        .accessibilityLabel("Customer ID \(cid)")
                }
            }
            if let reason = override.reason, !reason.isEmpty {
                Text(reason)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
                    .accessibilityLabel("Reason: \(reason)")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var scopeBadge: some View {
        Text(override.scope.rawValue.capitalized)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(override.scope == .customer ? .bizarreTeal : .bizarreOrange)
            .background(
                override.scope == .customer ? Color.bizarreTeal.opacity(0.15) : Color.bizarreOrange.opacity(0.15),
                in: Capsule()
            )
            .accessibilityLabel("Scope: \(override.scope.rawValue)")
    }
}
