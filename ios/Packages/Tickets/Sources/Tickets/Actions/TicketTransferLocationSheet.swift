#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §4.5 Transfer ticket to another store / location
//
// Multi-location tenants can move a ticket from one physical store to another.
// Route: POST /api/v1/tickets/:id/transfer { location_id, reason? }
// On success: dismiss + parent reloads.

// MARK: - ViewModel

@MainActor
@Observable
public final class TicketTransferLocationViewModel {
    public enum Phase: Sendable {
        case idle
        case loading
        case loaded([TenantLocation])
        case transferring
        case done
        case error(String)
    }

    public var phase: Phase = .idle
    public var selectedLocation: TenantLocation?
    public var reason: String = ""

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let ticketId: Int64

    public init(api: APIClient, ticketId: Int64) {
        self.api = api
        self.ticketId = ticketId
    }

    public var locations: [TenantLocation] {
        if case .loaded(let list) = phase { return list }
        return []
    }

    public func loadLocations() async {
        phase = .loading
        do {
            let list = try await api.listTenantLocations()
            phase = .loaded(list)
        } catch {
            phase = .error(error.localizedDescription)
            AppLog.ui.error("Transfer load locations failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func transfer() async {
        guard let loc = selectedLocation else { return }
        phase = .transferring
        do {
            try await api.transferTicket(ticketId: ticketId, toLocationId: loc.id, reason: reason.isEmpty ? nil : reason)
            phase = .done
        } catch {
            phase = .error(error.localizedDescription)
            AppLog.ui.error("Transfer submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - View

public struct TicketTransferLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketTransferLocationViewModel
    private let onSuccess: () -> Void

    public init(api: APIClient, ticketId: Int64, onSuccess: @escaping () -> Void) {
        _vm = State(wrappedValue: TicketTransferLocationViewModel(api: api, ticketId: ticketId))
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                formContent
            }
            .navigationTitle("Transfer to Location")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.loadLocations() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.phase == .transferring ? "Transferring…" : "Transfer") {
                        Task {
                            await vm.transfer()
                            if case .done = vm.phase {
                                onSuccess()
                                dismiss()
                            }
                        }
                    }
                    .disabled(vm.selectedLocation == nil || vm.phase == .transferring)
                    .accessibilityLabel("Transfer ticket to selected location")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Form

    @ViewBuilder
    private var formContent: some View {
        switch vm.phase {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading locations")
        case .error(let msg):
            VStack(spacing: BrandSpacing.md) {
                Text("Could not load locations")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.loadLocations() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .padding(BrandSpacing.lg)
        case .loaded(let list), .transferring:
            Form {
                Section("Destination location") {
                    if list.isEmpty {
                        Text("No other locations available")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else {
                        ForEach(list) { loc in
                            locationRow(loc)
                        }
                    }
                }
                Section("Reason (optional)") {
                    TextField("Why are you transferring this ticket?", text: $vm.reason, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .accessibilityLabel("Transfer reason")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
        case .done:
            EmptyView()
        }
    }

    private func locationRow(_ loc: TenantLocation) -> some View {
        let isSelected = vm.selectedLocation?.id == loc.id
        return Button {
            vm.selectedLocation = isSelected ? nil : loc
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(loc.name)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let address = loc.address, !address.isEmpty {
                        Text(address)
                            .font(.brandBodySmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(loc.name). \(isSelected ? "Selected." : "")")
    }
}

// MARK: - TenantLocation model + endpoint

/// A physical store location for multi-location tenants.
public struct TenantLocation: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let address: String?

    enum CodingKeys: String, CodingKey {
        case id, name, address
    }
}

public extension APIClient {
    /// `GET /api/v1/locations` — lists all tenant locations.
    /// Route: packages/server/src/routes/locations.routes.ts (GET /).
    func listTenantLocations() async throws -> [TenantLocation] {
        try await get("/api/v1/locations", as: [TenantLocation].self)
    }
}
#endif
