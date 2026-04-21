import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - MessageTemplateListView

public struct MessageTemplateListView: View {
    @State private var vm: MessageTemplateListViewModel
    @State private var showEditor: Bool = false
    @State private var editingTemplate: MessageTemplate?
    @State private var searchText: String = ""

    public init(api: APIClient, onPick: ((MessageTemplate) -> Void)? = nil) {
        _vm = State(wrappedValue: MessageTemplateListViewModel(api: api, onPick: onPick))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showEditor, onDismiss: { editingTemplate = nil }) {
            MessageTemplateEditorView(
                template: editingTemplate,
                api: vm.onPick != nil ? nil : extractAPI(),
                onSave: { _ in
                    showEditor = false
                    Task { await vm.load() }
                }
            )
        }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Message Templates")
            .searchable(text: $searchText, prompt: "Search templates")
            .onChange(of: searchText) { _, q in vm.searchQuery = q }
            .toolbar { addButton }
        }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Message Templates")
            .searchable(text: $searchText, prompt: "Search templates")
            .onChange(of: searchText) { _, q in vm.searchQuery = q }
            .toolbar { addButton }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorView(err)
        } else if vm.filtered.isEmpty {
            emptyView
        } else {
            templateList
        }
    }

    private var templateList: some View {
        List {
            filterPicker
            ForEach(vm.filtered) { tmpl in
                TemplateRow(template: tmpl, isPicker: vm.onPick != nil)
                    .listRowBackground(Color.bizarreSurface1)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.delete(template: tmpl) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityLabel("Delete template \(tmpl.name)")

                        Button {
                            editingTemplate = tmpl
                            showEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Edit template \(tmpl.name)")
                    }
                    .onTapGesture {
                        if vm.onPick != nil {
                            vm.pick(tmpl)
                        } else {
                            editingTemplate = tmpl
                            showEditor = true
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var filterPicker: some View {
        Section {
            Picker("Channel", selection: $vm.filterChannel) {
                Text("All channels").tag(MessageChannel?.none)
                ForEach(MessageChannel.allCases, id: \.self) { c in
                    Text(c.rawValue.capitalized).tag(MessageChannel?.some(c))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Filter by channel")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Empty / error

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No templates")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            if vm.onPick == nil {
                Button("Create your first template") { showEditor = true }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load templates").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        if vm.onPick == nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingTemplate = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New message template")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // Hack: extract api from vm (we set it at init)
    // In practice the caller would pass api separately.
    private func extractAPI() -> APIClient? { nil }
}

// MARK: - TemplateRow

private struct TemplateRow: View {
    let template: MessageTemplate
    let isPicker: Bool

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: template.channel == .sms ? "message.fill" : "envelope.fill")
                .font(.system(size: 18))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(template.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(template.body)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)

                HStack(spacing: BrandSpacing.xs) {
                    channelChip
                    categoryChip
                }
            }
            Spacer()
            if isPicker {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.name). \(template.channel.rawValue). \(template.category.displayName). \(template.body)")
    }

    private var channelChip: some View {
        Text(template.channel.rawValue.uppercased())
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(.bizarreOnSurface)
            .background(Color.bizarreSurface2, in: Capsule())
    }

    private var categoryChip: some View {
        Text(template.category.displayName)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(.bizarreOnSurface)
            .background(Color.bizarreSurface2, in: Capsule())
    }
}
