import SwiftUI
import Core
import DesignSystem

// MARK: - §3.1 Tile Customization — long-press → hide / reorder
//
// User can long-press a KPI tile to hide it or reorder the tile set.
// Ordering + visibility persisted in UserDefaults keyed per-tenant-user.
//
// Design: sheet with drag-to-reorder list + per-tile eye-toggle.
// Density applies on top (spacious / cozy / compact) — orthogonal to this.

// MARK: - Model

public struct DashboardTileConfig: Identifiable, Codable, Sendable, Equatable {
    public let id: String      // stable identifier (tile label slug)
    public var isVisible: Bool

    public init(id: String, isVisible: Bool = true) {
        self.id = id
        self.isVisible = isVisible
    }
}

// MARK: - Store

/// Persists tile order + visibility in UserDefaults.
/// Key: `dashboard.tileOrder` — JSON-encoded [DashboardTileConfig].
@MainActor
public final class DashboardTileOrderStore {

    public static let shared = DashboardTileOrderStore()

    private let key = "dashboard.tileOrder"

    /// Load the saved config, or return the given defaults if nothing is saved.
    public func load(defaults: [DashboardTileConfig]) -> [DashboardTileConfig] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let saved = try? JSONDecoder().decode([DashboardTileConfig].self, from: data)
        else {
            return defaults
        }
        // Merge: preserve order of saved; append any new tiles not yet saved.
        var result = saved
        let savedIds = Set(saved.map(\.id))
        for d in defaults where !savedIds.contains(d.id) {
            result.append(d)
        }
        return result
    }

    /// Persist the given order + visibility.
    public func save(_ config: [DashboardTileConfig]) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class DashboardTileCustomizationViewModel {
    public var tiles: [DashboardTileConfig]

    private let store: DashboardTileOrderStore

    public init(tiles: [DashboardTileConfig], store: DashboardTileOrderStore = .shared) {
        self.tiles = tiles
        self.store = store
    }

    public func moveRows(from offsets: IndexSet, to destination: Int) {
        tiles.move(fromOffsets: offsets, toOffset: destination)
        store.save(tiles)
    }

    public func toggleVisibility(id: String) {
        if let idx = tiles.firstIndex(where: { $0.id == id }) {
            tiles[idx].isVisible.toggle()
            store.save(tiles)
        }
    }

    public func reset(defaults: [DashboardTileConfig]) {
        store.reset()
        tiles = defaults
    }
}

// MARK: - Sheet View

/// Full-screen sheet (iPhone) / popover (iPad) for reordering and hiding tiles.
///
/// Presented by long-pressing a tile on the dashboard (see `DashboardView`).
public struct DashboardTileCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: DashboardTileCustomizationViewModel
    private let defaults: [DashboardTileConfig]

    public init(vm: DashboardTileCustomizationViewModel, defaults: [DashboardTileConfig]) {
        _vm = State(wrappedValue: vm)
        self.defaults = defaults
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Drag to reorder. Tap the eye to show or hide a tile.")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("Tiles") {
                    ForEach($vm.tiles) { $tile in
                        HStack(spacing: BrandSpacing.md) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)

                            Text(tile.id.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.brandBodyLarge())
                                .foregroundStyle(tile.isVisible ? .bizarreOnSurface : .bizarreOnSurfaceMuted)

                            Spacer()

                            Button {
                                vm.toggleVisibility(id: tile.id)
                            } label: {
                                Image(systemName: tile.isVisible ? "eye" : "eye.slash")
                                    .foregroundStyle(tile.isVisible ? .bizarreOrange : .bizarreOnSurfaceMuted)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tile.isVisible
                                ? "Hide \(tile.id.replacingOccurrences(of: "_", with: " ")) tile"
                                : "Show \(tile.id.replacingOccurrences(of: "_", with: " ")) tile")
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                    .onMove { offsets, dest in
                        vm.moveRows(from: offsets, to: dest)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Tiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        vm.reset(defaults: defaults)
                    }
                    .accessibilityLabel("Reset tile order and visibility to defaults")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
