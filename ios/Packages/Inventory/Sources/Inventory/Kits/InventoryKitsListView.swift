#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6 InventoryKitsListView
//
// Displays a list of inventory kits. Tapping a row navigates to detail.
// Supports pull-to-refresh and deletion with swipe action.
// Liquid Glass applied to the toolbar / navigation chrome only (per CLAUDE.md).
// iPad: NavigationSplitView sidebar + detail.
// iPhone: NavigationStack with inline detail push.

public struct InventoryKitsListView: View {
    @State private var vm: InventoryKitsListViewModel

    public init(repo: InventoryKitsRepository) {
        _vm = State(wrappedValue: InventoryKitsListViewModel(repo: repo))
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

    // MARK: - iPhone (compact)

    private var compactLayout: some View {
        NavigationStack {
            kitListContent
                .navigationTitle("Kits & BOM")
                .toolbar { navigationToolbar }
                .brandGlass()
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            kitListContent
                .navigationTitle("Kits & BOM")
                .toolbar { navigationToolbar }
                .brandGlass()
        } detail: {
            if let selectedId = vm.selectedKitId {
                InventoryKitDetailView(kitId: selectedId, repo: vm.repo)
            } else {
                ContentUnavailableView(
                    "Select a Kit",
                    systemImage: "shippingbox.and.arrow.backward",
                    description: Text("Choose a kit from the sidebar to see its components.")
                )
            }
        }
    }

    // MARK: - Shared list body

    private var kitListContent: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading && vm.kits.isEmpty {
                    ProgressView("Loading kits…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.kits.isEmpty {
                    ContentUnavailableView(
                        "No Kits Yet",
                        systemImage: "shippingbox.and.arrow.backward",
                        description: Text("Create a kit on the web app to see it here.")
                    )
                } else {
                    List(vm.kits, selection: Platform.isCompact ? nil : $vm.selectedKitId) {
                        kit in kitRow(kit)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            if let error = vm.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .padding()
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
    }

    // MARK: - Kit row

    private func kitRow(_ kit: InventoryKit) -> some View {
        Group {
            if Platform.isCompact {
                NavigationLink(destination: InventoryKitDetailView(kitId: kit.id, repo: vm.repo)) {
                    kitRowContent(kit)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await vm.deleteKit(id: kit.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } else {
                kitRowContent(kit)
                    .contentShape(Rectangle())
                    .hoverEffect(.highlight)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.deleteKit(id: kit.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private func kitRowContent(_ kit: InventoryKit) -> some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.title3)
                .foregroundStyle(.bizarreOrange)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(kit.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let desc = kit.description, !desc.isEmpty {
                    Text(desc)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let count = kit.itemCount {
                Text("\(count) component\(count == 1 ? "" : "s")")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if !Platform.isCompact {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kit.name), \(kit.itemCount.map { "\($0) components" } ?? "")")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            EmptyView() // Create flow is web-only for now; server requires manager/admin role
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class InventoryKitsListViewModel {
    var kits: [InventoryKit] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var selectedKitId: Int64?

    let repo: InventoryKitsRepository

    init(repo: InventoryKitsRepository) {
        self.repo = repo
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            kits = try await repo.listKits()
        } catch {
            errorMessage = "Failed to load kits: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        isLoading = false
        await load()
    }

    func deleteKit(id: Int64) async {
        do {
            try await repo.deleteKit(id: id)
            kits = kits.filter { $0.id != id }
            if selectedKitId == id { selectedKitId = nil }
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}
#endif
