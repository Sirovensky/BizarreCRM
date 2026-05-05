import SwiftUI
import Core
import DesignSystem

// MARK: - §60.4 CurrentLocationPickerView

/// Settings screen that lets the user choose their active "home" location.
///
/// Backed by real server endpoints:
///   - GET  /api/v1/locations/me/default-location  — resolve current default
///   - POST /api/v1/locations/users/:userId/locations/:locationId  — assign with is_primary=1
///
/// The chosen location ID is also persisted locally in UserDefaults via
/// `LocationContext` so the chip updates immediately without a network round-trip.

public struct CurrentLocationPickerView: View {
    @State private var vm: CurrentLocationPickerViewModel
    @State private var context: LocationContext

    public init(
        repo: any LocationUserAssignmentRepository,
        userId: String,
        context: LocationContext = .shared
    ) {
        _vm = State(initialValue: CurrentLocationPickerViewModel(repo: repo, userId: userId))
        _context = State(wrappedValue: context)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneList
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Home Location")
        .task { await vm.load() }
        .overlay {
            if vm.isSaving {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("OK", role: .cancel) { vm.clearError() }
        } message: {
            if let msg = vm.errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: iPhone — simple List

    @ViewBuilder
    private var iPhoneList: some View {
        switch vm.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
        default:
            List {
                Section {
                    ForEach(vm.locations.filter(\.active)) { loc in
                        locationRow(loc)
                    }
                } header: {
                    Text("Select your primary work location")
                        .textCase(nil)
                        .font(.subheadline)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } footer: {
                    Text("This location is pre-selected when you open tickets, invoices, or inventory.")
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .refreshable { await vm.load() }
        }
    }

    // MARK: iPad — wider form layout

    @ViewBuilder
    private var iPadLayout: some View {
        switch vm.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
        default:
            Form {
                Section {
                    ForEach(vm.locations.filter(\.active)) { loc in
                        locationRow(loc)
                            .hoverEffect(.highlight)
                    }
                } header: {
                    Text("Active locations")
                } footer: {
                    Text("Your home location is pre-selected when creating tickets, invoices, and inventory entries.")
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: Shared row

    @ViewBuilder
    private func locationRow(_ loc: Location) -> some View {
        Button {
            Task { await select(loc) }
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isSelected(loc) ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(loc.name)
                        .font(.headline)
                        .foregroundStyle(.bizarreOnSurface)
                    Text("\(loc.city), \(loc.region) \(loc.timezone)")
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Spacer()

                if isSelected(loc) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .font(.title3)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(loc.name), \(loc.city)")
        .accessibilityAddTraits(isSelected(loc) ? .isSelected : [])
        .accessibilityHint(isSelected(loc) ? "Currently selected" : "Double-tap to set as home location")
    }

    private func isSelected(_ loc: Location) -> Bool {
        loc.id == vm.activeLocationId
    }

    private func select(_ loc: Location) async {
        let previousId = vm.activeLocationId
        await vm.selectLocation(loc.id)
        // Only mirror into LocationContext if the selection succeeded (no error set)
        if vm.errorMessage == nil && vm.activeLocationId != previousId {
            context.switch(locationId: loc.id)
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
public final class CurrentLocationPickerViewModel {

    public enum LoadState: Equatable {
        case idle, loading, loaded, error(String)
    }

    public private(set) var locations: [Location] = []
    public private(set) var activeLocationId: String = ""
    public private(set) var loadState: LoadState = .idle
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String? = nil

    private let repo: any LocationUserAssignmentRepository
    private let userId: String

    public init(repo: any LocationUserAssignmentRepository, userId: String) {
        self.repo = repo
        self.userId = userId
    }

    // MARK: Intents

    public func load() async {
        loadState = .loading
        do {
            async let locs = repo.fetchLocations()
            async let defaultLoc = repo.fetchDefaultLocation()
            let (allLocations, defaultLocation) = try await (locs, defaultLoc)
            locations = allLocations
            activeLocationId = defaultLocation?.id ?? ""
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// Assigns the given location as the user's primary and updates local state.
    public func selectLocation(_ locationId: String) async {
        guard locationId != activeLocationId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repo.assignUserLocation(
                userId: userId,
                locationId: locationId,
                isPrimary: true
            )
            activeLocationId = locationId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearError() {
        errorMessage = nil
    }
}
