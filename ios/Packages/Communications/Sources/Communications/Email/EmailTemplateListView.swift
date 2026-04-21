import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - EmailTemplateListViewModel

@MainActor
@Observable
public final class EmailTemplateListViewModel {

    // MARK: - State

    public internal(set) var templates: [EmailTemplate] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Filters

    public var filterCategory: EmailTemplateCategory? = nil
    public var searchQuery: String = ""

    public var filtered: [EmailTemplate] {
        templates.filter { t in
            let matchCat = filterCategory.map { $0 == t.category } ?? true
            let q = searchQuery.trimmingCharacters(in: .whitespaces)
            let matchSearch = q.isEmpty
                || t.name.localizedCaseInsensitiveContains(q)
                || t.subject.localizedCaseInsensitiveContains(q)
            return matchCat && matchSearch
        }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored public var onPick: ((EmailTemplate) -> Void)?

    public init(api: APIClient, onPick: ((EmailTemplate) -> Void)? = nil) {
        self.api = api
        self.onPick = onPick
    }

    // MARK: - Actions

    public func load() async {
        if templates.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            templates = try await api.listEmailTemplates()
        } catch {
            AppLog.ui.error("Email templates load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func delete(template: EmailTemplate) async {
        let id = template.id
        templates.removeAll { $0.id == id }
        do {
            try await api.deleteEmailTemplate(id: id)
        } catch {
            AppLog.ui.error("Email template delete failed: \(error.localizedDescription, privacy: .public)")
            await load()
            errorMessage = error.localizedDescription
        }
    }

    public func pick(_ template: EmailTemplate) {
        onPick?(template)
    }
}

// MARK: - EmailTemplateListView

public struct EmailTemplateListView: View {
    @State private var vm: EmailTemplateListViewModel
    @State private var showEditor = false
    @State private var editingTemplate: EmailTemplate?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let onPick: ((EmailTemplate) -> Void)?

    public init(api: APIClient, onPick: ((EmailTemplate) -> Void)? = nil) {
        self.api = api
        self.onPick = onPick
        _vm = State(wrappedValue: EmailTemplateListViewModel(api: api, onPick: onPick))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar { toolbarItems }
        .sheet(isPresented: $showEditor) {
            EmailTemplateEditorView(
                template: editingTemplate,
                api: api,
                onSave: { saved in
                    if let idx = vm.templates.firstIndex(where: { $0.id == saved.id }) {
                        vm.templates[idx] = saved
                    } else {
                        vm.templates.append(saved)
                    }
                    showEditor = false
                }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.templates.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.templates.isEmpty {
            errorState(err)
        } else {
            templateList
        }
    }

    private var templateList: some View {
        List {
            // Filter chips
            if !vm.templates.isEmpty {
                categoryFilter
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if vm.filtered.isEmpty {
                Text("No templates")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(vm.filtered) { template in
                    templateRow(template)
                }
                .onDelete { offsets in
                    for idx in offsets {
                        Task { await vm.delete(template: vm.filtered[idx]) }
                    }
                }
            }
        }
        .searchable(text: $vm.searchQuery, prompt: "Search templates")
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                categoryChip(nil, label: "All")
                ForEach(EmailTemplateCategory.allCases, id: \.self) { cat in
                    categoryChip(cat, label: cat.displayName)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
    }

    private func categoryChip(_ cat: EmailTemplateCategory?, label: String) -> some View {
        Button {
            vm.filterCategory = cat
        } label: {
            Text(label)
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(vm.filterCategory == cat ? .black : .bizarreOnSurface)
                .background(vm.filterCategory == cat ? Color.bizarreOrange : Color.bizarreSurface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(label)")
    }

    private func templateRow(_ template: EmailTemplate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(template.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(template.subject)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
                Text(template.category.displayName)
                    .font(.brandMono(size: 11))
                    .foregroundStyle(.bizarreOrange)
            }
            Spacer()
            if onPick != nil {
                Button("Use") { vm.pick(template) }
                    .buttonStyle(.brandGlass)
                    .accessibilityLabel("Use template \(template.name)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let pick = onPick {
                pick(template)
            } else {
                editingTemplate = template
                showEditor = true
            }
        }
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
        .contextMenu {
            Button("Edit") {
                editingTemplate = template
                showEditor = true
            }
            Button("Delete", role: .destructive) {
                Task { await vm.delete(template: template) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.name). Subject: \(template.subject). Category: \(template.category.displayName)")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
            Text("Couldn't load templates").font(.brandTitleMedium())
            Text(message).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.brandGlassProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                editingTemplate = nil
                showEditor = true
            } label: {
                Label("New Template", systemImage: "plus")
            }
            .accessibilityLabel("Create new email template")
        }
    }
}
