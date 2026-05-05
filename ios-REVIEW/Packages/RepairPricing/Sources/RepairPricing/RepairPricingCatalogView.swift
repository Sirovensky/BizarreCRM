import SwiftUI
import Core
import DesignSystem
import Networking

/// §43.1 Root catalog browser.
///
/// Layout:
///   - iPhone  → `NavigationStack` with family chips + lazy grid
///   - iPad    → `NavigationSplitView` with sidebar (chips + grid) + detail pane
///
/// Glass is applied to the navigation chrome only — content tiles use
/// `bizarreSurface1` per design token rules.
@MainActor
public struct RepairPricingCatalogView: View {
    @State private var vm: RepairPricingViewModel
    @State private var searchText: String = ""
    @State private var selectedTemplate: DeviceTemplate?

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: RepairPricingViewModel(api: api))
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

    // MARK: - iPhone layout

    private var phoneLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                phoneContent
            }
            .navigationTitle("Repair Catalog")
            .searchable(text: $searchText, prompt: "Search devices")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            #if canImport(UIKit)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
        }
    }

    @ViewBuilder
    private var phoneContent: some View {
        switch vm.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading repair catalog")
        case .failed(let msg):
            errorView(message: msg)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.base) {
                    familyChipsRow
                        .padding(.horizontal, BrandSpacing.base)
                    deviceGrid
                        .padding(.horizontal, BrandSpacing.base)
                }
                .padding(.top, BrandSpacing.sm)
                .padding(.bottom, BrandSpacing.xxl)
            }
        }
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                padSidebar
            }
            .navigationTitle("Repair Catalog")
            .searchable(text: $searchText, prompt: "Search devices")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
            #if canImport(UIKit)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if let selected = selectedTemplate {
                    RepairPricingDeviceDetailView(template: selected, api: api)
                } else {
                    padEmptyDetail
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var padSidebar: some View {
        switch vm.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading repair catalog")
        case .failed(let msg):
            errorView(message: msg)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.base) {
                    familyChipsRow
                        .padding(.horizontal, BrandSpacing.base)
                    deviceGrid
                        .padding(.horizontal, BrandSpacing.base)
                }
                .padding(.top, BrandSpacing.sm)
                .padding(.bottom, BrandSpacing.xxl)
            }
        }
    }

    private var padEmptyDetail: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Select a device")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Choose a device from the catalog to view its repair services.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared subviews

    /// Horizontal scrolling chips for family filter (Apple / Samsung / Google / Other).
    private var familyChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                FamilyChip(label: "All", isSelected: vm.family == nil) {
                    vm.family = nil
                }
                ForEach(vm.availableFamilies, id: \.self) { fam in
                    FamilyChip(label: fam, isSelected: vm.family == fam) {
                        vm.family = (vm.family == fam) ? nil : fam
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
    }

    /// Adaptive grid of device tiles.
    private var deviceGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: BrandSpacing.md)]
        return LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
            ForEach(vm.filteredTemplates) { template in
                DeviceTile(template: template) {
                    selectedTemplate = template
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(tilA11yLabel(for: template))
            }
        }
    }

    @ViewBuilder
    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load catalog")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tilA11yLabel(for template: DeviceTemplate) -> String {
        var parts = [template.name]
        if let model = template.model { parts.append(model) }
        if let family = template.family { parts.append(family) }
        if let count = template.services?.count { parts.append("\(count) services") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Family chip

private struct FamilyChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(isSelected ? .bizarreOnOrange : .bizarreOnSurface)
                .background(
                    isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(label) filter\(isSelected ? ", selected" : "")")
    }
}

// MARK: - Device tile

private struct DeviceTile: View {
    let template: DeviceTemplate
    let action: () -> Void

    private var serviceCount: Int { template.services?.count ?? 0 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: BrandSpacing.sm) {
                thumbnailView
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.bizarreOrange)
                VStack(spacing: BrandSpacing.xxs) {
                    Text(template.model ?? template.name)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let family = template.family {
                        Text(family)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                    if serviceCount > 0 {
                        Text("\(serviceCount) service\(serviceCount == 1 ? "" : "s")")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let urlString = template.thumbnailUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    fallbackIcon
                case .empty:
                    ProgressView()
                @unknown default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: deviceSystemImage(for: template.family))
            .resizable()
            .scaledToFit()
    }
}

// MARK: - Helpers

private func deviceSystemImage(for family: String?) -> String {
    switch family?.lowercased() {
    case "apple":   return "iphone.gen3"
    case "samsung": return "iphone.gen2"
    case "google":  return "iphone.gen1"
    case "tablet":  return "ipad"
    default:        return "iphone"
    }
}
