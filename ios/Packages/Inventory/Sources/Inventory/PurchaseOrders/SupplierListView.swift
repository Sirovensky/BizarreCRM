#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class SupplierListViewModel {
    public private(set) var suppliers: [Supplier] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var editTarget: Supplier?
    public var showAdd: Bool = false

    @ObservationIgnored private let repo: SupplierRepository

    public init(repo: SupplierRepository) { self.repo = repo }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            suppliers = try await repo.list()
        } catch {
            AppLog.ui.error("Supplier list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func delete(_ supplier: Supplier) async {
        do {
            try await repo.delete(id: supplier.id)
            suppliers = suppliers.filter { $0.id != supplier.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct SupplierListView: View {
    @State private var vm: SupplierListViewModel
    @State private var selectedSupplier: Supplier?
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: SupplierListViewModel(
            repo: LiveSupplierRepository(api: api)))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    // MARK: iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                contentBody
            }
            .navigationTitle("Suppliers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(isPresented: $vm.showAdd) {
                SupplierEditorSheet(supplier: nil, api: api) { Task { await vm.load() } }
            }
            .sheet(item: $vm.editTarget) { s in
                SupplierEditorSheet(supplier: s, api: api) { Task { await vm.load() } }
            }
        }
    }

    // MARK: iPad

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                contentBody
            }
            .navigationTitle("Suppliers")
            .toolbar { toolbarItems }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 480)
            .sheet(isPresented: $vm.showAdd) {
                SupplierEditorSheet(supplier: nil, api: api) { Task { await vm.load() } }
            }
            .sheet(item: $vm.editTarget) { s in
                SupplierEditorSheet(supplier: s, api: api) { Task { await vm.load() } }
            }
        } detail: {
            if let s = selectedSupplier {
                supplierDetail(s)
            } else {
                emptyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { vm.showAdd = true } label: {
                Image(systemName: "plus").accessibilityLabel("Add Supplier")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentBody: some View {
        if vm.isLoading && vm.suppliers.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = vm.errorMessage {
            errorView(msg)
        } else if vm.suppliers.isEmpty {
            emptyState
        } else {
            supplierList
        }
    }

    private var supplierList: some View {
        List {
            ForEach(vm.suppliers) { supplier in
                supplierRow(supplier)
                    .listRowBackground(Color.bizarreSurface1)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.delete(supplier) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            vm.editTarget = supplier
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.bizarreOrange)
                    }
                    .contextMenu {
                        Button { vm.editTarget = supplier } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task { await vm.delete(supplier) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .onTapGesture {
                        if !Platform.isCompact { selectedSupplier = supplier }
                        else { vm.editTarget = supplier }
                    }
                    .hoverEffect(.highlight)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func supplierRow(_ s: Supplier) -> some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(s.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(s.email)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
                Text("Lead time: \(s.leadTimeDays)d · \(s.paymentTerms)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .imageScale(.small)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(s.name), \(s.email)")
    }

    private func supplierDetail(_ s: Supplier) -> some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                Text(s.name).font(.brandHeadlineMedium()).foregroundStyle(.bizarreOnSurface)
                if let contact = s.contactName {
                    Text(contact).font(.brandBodyLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Text(s.email).font(.brandMono(size: 13)).foregroundStyle(.bizarreOnSurfaceMuted).textSelection(.enabled)
                Text(s.phone).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).textSelection(.enabled)
                Text(s.address).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Terms: \(s.paymentTerms)").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Lead time: \(s.leadTimeDays) days").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                Button("Edit Supplier") { vm.editTarget = s }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .keyboardShortcut("e", modifiers: .command)
                Spacer()
            }
            .padding(BrandSpacing.lg)
        }
        .navigationTitle(s.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyDetail: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "building.2")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Select a supplier")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "building.2")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No suppliers yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Button("Add Supplier") { vm.showAdd = true }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No suppliers. Tap to add one.")
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load suppliers")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
