import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §43.5 Device Template List View (Admin)

/// Admin list: Settings → Repair Pricing → Device Templates.
/// iPhone: NavigationStack list + full-screen editor push.
/// iPad: NavigationSplitView sidebar list + editor in detail column.
@MainActor
public struct DeviceTemplateListView: View {

    @State private var vm: DeviceTemplateListViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: DeviceTemplateListViewModel(api: api))
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
            listContent
                .navigationTitle("Device Templates")
                #if canImport(UIKit)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            DeviceTemplateEditorView(api: vm.api) { saved in
                                vm.onSaved(saved)
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New template")
                        .accessibilityIdentifier("templateList.new")
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        familyMenu
                    }
                }
        }
    }

    // MARK: - iPad

    private var padLayout: some View {
        NavigationSplitView {
            listContent
                .navigationTitle("Device Templates")
                #if canImport(UIKit)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            vm.selectedTemplate = nil
                            vm.showingEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New template")
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        familyMenu
                    }
                }
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if vm.showingEditor {
                    DeviceTemplateEditorView(
                        api: vm.api,
                        editingTemplate: vm.selectedTemplate
                    ) { saved in
                        vm.onSaved(saved)
                        vm.showingEditor = false
                    }
                } else if let selected = vm.selectedTemplate {
                    RepairPricingDeviceDetailView(template: selected, api: vm.api)
                } else {
                    padEmptyDetail
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared list content

    @ViewBuilder
    private var listContent: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading templates")
            } else if let err = vm.errorMessage {
                errorView(message: err)
            } else if vm.filteredTemplates.isEmpty {
                emptyView
            } else {
                templateList
            }
        }
    }

    private var templateList: some View {
        List {
            ForEach(vm.filteredTemplates) { template in
                Button {
                    vm.selectedTemplate = template
                    vm.showingEditor = false
                } label: {
                    TemplateListRow(template: template)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.bizarreSurface1)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await vm.delete(template: template) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        vm.selectedTemplate = template
                        vm.showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.bizarreOrange)
                }
                #if canImport(UIKit)
                .contextMenu {
                    Button {
                        vm.selectedTemplate = template
                        vm.showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Task { await vm.delete(template: template) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .hoverEffect(.highlight)
                #endif
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Sub-views

    private var familyMenu: some View {
        Menu {
            Button("All") { vm.familyFilter = nil }
            ForEach(vm.availableFamilies, id: \.self) { fam in
                Button(fam) { vm.familyFilter = fam }
            }
        } label: {
            Label(vm.familyFilter ?? "All", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter by family")
    }

    private var padEmptyDetail: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Select or create a template")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Choose a template to view details or tap + to add a new one.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Templates")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Add a device template to get started.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load templates")
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

// MARK: - List Row

private struct TemplateListRow: View {
    let template: DeviceTemplate

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: deviceIcon(for: template.family))
                .font(.system(size: 24))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(template.model ?? template.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let fam = template.family {
                    Text(fam)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let count = template.services?.count, count > 0 {
                    Text("\(count) service\(count == 1 ? "" : "s")")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([
            template.model ?? template.name,
            template.family,
            template.services.map { "\($0.count) services" }
        ].compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - Helper

private func deviceIcon(for family: String?) -> String {
    switch family?.lowercased() {
    case "apple":   return "iphone.gen3"
    case "samsung": return "iphone.gen2"
    case "google":  return "iphone.gen1"
    case "tablet":  return "ipad"
    default:        return "iphone"
    }
}

// MARK: - List ViewModel

/// Backing ViewModel for `DeviceTemplateListView`.
@MainActor
@Observable
final class DeviceTemplateListViewModel {
    let api: APIClient

    var templates: [DeviceTemplate] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var familyFilter: String? = nil
    var selectedTemplate: DeviceTemplate? = nil
    var showingEditor: Bool = false

    var availableFamilies: [String] {
        var seen = Set<String>()
        return templates.compactMap { $0.family }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var filteredTemplates: [DeviceTemplate] {
        guard let fam = familyFilter else { return templates }
        return templates.filter { $0.family?.lowercased() == fam.lowercased() }
    }

    init(api: APIClient) { self.api = api }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await api.listDeviceTemplates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(template: DeviceTemplate) async {
        do {
            try await api.deleteDeviceTemplate(id: template.id)
            templates = templates.filter { $0.id != template.id }
            if selectedTemplate?.id == template.id {
                selectedTemplate = nil
                showingEditor = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func onSaved(_ template: DeviceTemplate) {
        // Replace or insert
        if let idx = templates.firstIndex(where: { $0.id == template.id }) {
            var updated = templates
            updated[idx] = template
            templates = updated
        } else {
            templates = templates + [template]
        }
        selectedTemplate = template
    }
}
