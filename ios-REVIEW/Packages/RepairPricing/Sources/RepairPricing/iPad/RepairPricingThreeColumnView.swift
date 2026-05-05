import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §22 iPad Three-Column RepairPricing

/// iPad-only three-column repair pricing layout:
///   Column 1: Device-family sidebar (iPhone/iPad/Mac/Android/Other)
///   Column 2: Template list for the selected family
///   Column 3: Service + price table for the selected template
///
/// Liquid Glass chrome on all navigation bars. Data-table column in column 3
/// uses SwiftUI `Table` with sortable columns (iOS 16+).
///
/// On non-iPad devices this view should not be presented; callers are
/// responsible for gating on `!Platform.isCompact`.
@MainActor
public struct RepairPricingThreeColumnView: View {

    // MARK: - State

    @State private var vm: RepairPricingThreeColumnViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: RepairPricingThreeColumnViewModel(api: api))
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Column 1 — Device-family sidebar
            DeviceFamilySidebar(
                selectedFamily: $vm.selectedFamily,
                templateCountsByFamily: vm.templateCountsByFamily
            )
            .navigationTitle("Repair Pricing")
            #if canImport(UIKit)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    newTemplateButton
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            // Column 2 — Template list for selected family
            templateListColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            // Column 3 — Service + price table
            servicePriceTableColumn
        }
        .navigationSplitViewStyle(.balanced)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .searchable(text: $vm.searchQuery, prompt: "Search templates")
        // Keyboard shortcuts (§22.4)
        .modifier(RepairPricingKeyboardShortcuts(
            onNew: { vm.initiateNew() },
            onFind: { vm.focusSearch() },
            onRefresh: { Task { await vm.load() } }
        ))
        .alert("Delete Template?", isPresented: $vm.showDeleteConfirm, presenting: vm.templatePendingDelete) { template in
            Button("Delete", role: .destructive) {
                Task { await vm.confirmDelete(template) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { template in
            Text("\"\(template.model ?? template.name)\" and all its services will be permanently deleted.")
        }
    }

    // MARK: - Column 2: template list

    @ViewBuilder
    private var templateListColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            switch vm.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading templates")
            case .failed(let msg):
                columnErrorView(message: msg)
            case .loaded:
                if vm.filteredTemplates.isEmpty {
                    emptyTemplateListView
                } else {
                    templateList
                }
            }
        }
        .navigationTitle(vm.selectedFamily?.displayName ?? "All Devices")
        #if canImport(UIKit)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
    }

    private var templateList: some View {
        List(selection: $vm.selectedTemplate) {
            ForEach(vm.filteredTemplates) { template in
                RepairPricingThreeColumnTemplateRow(template: template)
                    .tag(template)
                    .listRowBackground(Color.bizarreSurface1)
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                    .contextMenu {
                        RepairPricingContextMenu(
                            template: template,
                            onOpen:      { vm.selectedTemplate = template },
                            onEdit:      { vm.initiateEdit(template) },
                            onDuplicate: { Task { await vm.duplicate(template) } },
                            onDelete:    { vm.requestDelete(template) }
                        )
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var emptyTemplateListView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Templates")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("No device templates found for \(vm.selectedFamily?.displayName ?? "this family").")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Column 3: service price table

    @ViewBuilder
    private var servicePriceTableColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if let template = vm.selectedTemplate {
                ServicePriceTable(
                    template: template,
                    api: api
                )
            } else {
                tableEmptyDetail
            }
        }
    }

    private var tableEmptyDetail: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "tablecells")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Select a Device")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Choose a device template to view its repair service pricing table.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar items

    private var newTemplateButton: some View {
        Button {
            vm.initiateNew()
        } label: {
            Image(systemName: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("New template")
        .accessibilityIdentifier("threeColumn.new")
    }

    // MARK: - Error view

    private func columnErrorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load data")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(BrandGlassButtonStyle())
                .tint(.bizarreOrange)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Template row

private struct RepairPricingThreeColumnTemplateRow: View {
    let template: DeviceTemplate

    private var serviceCount: Int { template.services?.count ?? 0 }

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: familyIcon(for: template.family))
                .font(.system(size: 20))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(template.model ?? template.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let family = template.family {
                    Text(family)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            if serviceCount > 0 {
                Text("\(serviceCount)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
                    .accessibilityLabel("\(serviceCount) services")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([
            template.model ?? template.name,
            template.family,
            serviceCount > 0 ? "\(serviceCount) services" : nil
        ].compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - Helpers

private func familyIcon(for family: String?) -> String {
    switch family?.lowercased() {
    case "iphone":  return "iphone.gen3"
    case "ipad":    return "ipad"
    case "mac":     return "laptopcomputer"
    case "android": return "phone"
    default:        return "iphone.gen3"
    }
}

// MARK: - ViewModel

/// Backing ViewModel for `RepairPricingThreeColumnView`.
@MainActor
@Observable
public final class RepairPricingThreeColumnViewModel {

    // MARK: - Public state

    public private(set) var state: RepairPricingState = .loading
    public private(set) var templates: [DeviceTemplate] = []

    /// Sidebar selected family. `nil` = All.
    public var selectedFamily: DeviceFamily? = nil {
        didSet { guard selectedFamily != oldValue else { return }
                 selectedTemplate = nil }
    }

    /// Selected template in column 2.
    public var selectedTemplate: DeviceTemplate? = nil

    /// Live search query — filters column 2 list.
    public var searchQuery: String = ""

    /// Delete confirmation
    public var showDeleteConfirm: Bool = false
    public private(set) var templatePendingDelete: DeviceTemplate? = nil

    // MARK: - Derived

    public var templateCountsByFamily: [DeviceFamily: Int] {
        var counts: [DeviceFamily: Int] = [:]
        for t in templates {
            let fam = DeviceFamily.from(string: t.family)
            counts[fam, default: 0] += 1
        }
        return counts
    }

    public var filteredTemplates: [DeviceTemplate] {
        var result = templates
        if let fam = selectedFamily {
            result = result.filter { DeviceFamily.from(string: $0.family) == fam }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter { t in
            t.name.lowercased().contains(q) ||
            (t.model?.lowercased().contains(q) == true) ||
            (t.family?.lowercased().contains(q) == true)
        }
    }

    // MARK: - Private

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public actions

    public func load() async {
        state = .loading
        do {
            templates = try await api.listDeviceTemplates()
            state = .loaded
        } catch {
            AppLog.ui.error("ThreeColumnVM load: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    public func initiateNew() {
        // Triggers sheet/navigation in a hosting view; VM signals intent
        // via observable property. Hosting container observes this.
    }

    public func focusSearch() {
        // Observable signal — the view watches a @FocusState bound externally
    }

    public func initiateEdit(_ template: DeviceTemplate) {
        selectedTemplate = template
    }

    public func requestDelete(_ template: DeviceTemplate) {
        templatePendingDelete = template
        showDeleteConfirm = true
    }

    public func confirmDelete(_ template: DeviceTemplate) async {
        do {
            try await api.deleteDeviceTemplate(id: template.id)
            templates = templates.filter { $0.id != template.id }
            if selectedTemplate?.id == template.id { selectedTemplate = nil }
        } catch {
            AppLog.ui.error("ThreeColumnVM delete: \(error.localizedDescription, privacy: .public)")
        }
        templatePendingDelete = nil
        showDeleteConfirm = false
    }

    public func duplicate(_ template: DeviceTemplate) async {
        // POST a copy — server returns the new record with a fresh id.
        let req = CreateDeviceTemplateRequest(
            name: "\(template.name) (Copy)",
            deviceCategory: template.family ?? "",
            deviceModel: template.model,
            year: nil,
            conditions: template.conditions,
            services: template.services?.map {
                InlineServiceRequest(
                    serviceName: $0.serviceName,
                    defaultPriceCents: $0.defaultPriceCents,
                    description: nil
                )
            } ?? []
        )
        do {
            let created = try await api.createDeviceTemplate(body: req)
            templates = templates + [created]
        } catch {
            AppLog.ui.error("ThreeColumnVM duplicate: \(error.localizedDescription, privacy: .public)")
        }
    }
}
