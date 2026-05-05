import SwiftUI
import Core
import DesignSystem

// MARK: - §60.5 LocationPermissionsMatrix

/// Manager/Admin view: see and edit which users are assigned to which locations.
///
/// Unlike `LocationPermissionsView` (which uses a stub employee-access endpoint
/// not present in the server), this component is backed entirely by real endpoints:
///   GET  /api/v1/locations/users/:userId/locations       — list assignments
///   POST /api/v1/locations/users/:userId/locations/:locationId  — assign (manager+)
///   DELETE /api/v1/locations/users/:userId/locations/:locationId  — unassign (manager+)
///
/// iPad:  3-column Grid (user × location matrix) with toggle chips
/// iPhone: Sectioned list per user → location rows with toggle buttons

public struct LocationPermissionsMatrix: View {
    @State private var vm: LocationPermissionsMatrixViewModel

    /// `users` must be pre-loaded by the caller (e.g. from the Users package).
    public init(
        repo: any LocationUserAssignmentRepository,
        locations: [Location],
        users: [PermissionMatrixUser]
    ) {
        _vm = State(initialValue: LocationPermissionsMatrixViewModel(
            repo: repo,
            locations: locations,
            users: users
        ))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Location Assignments")
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

    // MARK: iPhone — sectioned list

    @ViewBuilder
    private var iPhoneLayout: some View {
        switch vm.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
        default:
            List {
                ForEach(vm.users) { user in
                    Section(user.displayName) {
                        ForEach(vm.locations.filter(\.active)) { loc in
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(vm.isAssigned(userId: user.id, locationId: loc.id)
                                                     ? .bizarreOrange : .bizarreOnSurfaceMuted)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                    Text(loc.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.bizarreOnSurface)
                                    if let role = vm.roleAtLocation(userId: user.id, locationId: loc.id) {
                                        Text(role)
                                            .font(.caption)
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                    }
                                }
                                Spacer()
                                Toggle(
                                    isOn: Binding(
                                        get: { vm.isAssigned(userId: user.id, locationId: loc.id) },
                                        set: { on in Task { await vm.toggle(userId: user.id, locationId: loc.id, on: on) } }
                                    )
                                ) {
                                    EmptyView()
                                }
                                .labelsHidden()
                                .accessibilityLabel("Assign \(user.displayName) to \(loc.name)")
                            }
                        }
                    }
                }
            }
            .refreshable { await vm.load() }
        }
    }

    // MARK: iPad — matrix grid

    @ViewBuilder
    private var iPadLayout: some View {
        switch vm.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
        default:
            ScrollView([.horizontal, .vertical]) {
                Grid(
                    horizontalSpacing: DesignTokens.Spacing.md,
                    verticalSpacing: DesignTokens.Spacing.xs
                ) {
                    // Header row
                    GridRow {
                        Text("User")
                            .font(.headline)
                            .frame(width: 180, alignment: .leading)
                        ForEach(vm.locations.filter(\.active)) { loc in
                            Text(loc.name)
                                .font(.caption.bold())
                                .frame(width: 90)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    Divider()

                    // Data rows
                    ForEach(vm.users) { user in
                        GridRow {
                            Text(user.displayName)
                                .font(.subheadline)
                                .frame(width: 180, alignment: .leading)
                                .textSelection(.enabled)
                                .lineLimit(1)

                            ForEach(vm.locations.filter(\.active)) { loc in
                                AssignmentCell(
                                    isAssigned: vm.isAssigned(userId: user.id, locationId: loc.id),
                                    isPrimary: vm.isPrimary(userId: user.id, locationId: loc.id)
                                ) {
                                    Task {
                                        let current = vm.isAssigned(userId: user.id, locationId: loc.id)
                                        await vm.toggle(userId: user.id, locationId: loc.id, on: !current)
                                    }
                                }
                                .frame(width: 90)
                            }
                        }
                    }
                }
                .padding(DesignTokens.Spacing.lg)
            }
        }
    }
}

// MARK: - AssignmentCell (iPad)

private struct AssignmentCell: View {
    let isAssigned: Bool
    let isPrimary: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(isAssigned ? Color.bizarreOrange.opacity(0.15) : Color.bizarreSurface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .strokeBorder(
                                isAssigned ? Color.bizarreOrange : Color.bizarreSurface2,
                                lineWidth: 1.5
                            )
                    )

                if isAssigned {
                    VStack(spacing: 1) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.bizarreOrange)
                        if isPrimary {
                            Text("primary")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
            }
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .brandHover()
        .accessibilityLabel(isAssigned ? "Assigned\(isPrimary ? ", primary" : "")" : "Not assigned")
        .accessibilityHint("Double-tap to toggle")
    }
}

// MARK: - Model

/// Lightweight user record supplied by the caller.
public struct PermissionMatrixUser: Identifiable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

// MARK: - ViewModel

@Observable
@MainActor
public final class LocationPermissionsMatrixViewModel {

    public enum LoadState: Equatable {
        case idle, loading, loaded, error(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String? = nil

    /// Keyed by userId → [UserLocationAssignment]
    private var assignments: [String: [UserLocationAssignment]] = [:]

    public let locations: [Location]
    public let users: [PermissionMatrixUser]

    private let repo: any LocationUserAssignmentRepository

    public init(
        repo: any LocationUserAssignmentRepository,
        locations: [Location],
        users: [PermissionMatrixUser]
    ) {
        self.repo = repo
        self.locations = locations
        self.users = users
    }

    // MARK: Queries

    public func isAssigned(userId: String, locationId: String) -> Bool {
        assignments[userId]?.contains(where: { $0.location.id == locationId }) ?? false
    }

    public func isPrimary(userId: String, locationId: String) -> Bool {
        assignments[userId]?.first(where: { $0.location.id == locationId })?.isPrimary ?? false
    }

    public func roleAtLocation(userId: String, locationId: String) -> String? {
        assignments[userId]?.first(where: { $0.location.id == locationId })?.roleAtLocation
    }

    // MARK: Intents

    public func load() async {
        loadState = .loading
        do {
            // Fetch assignments for every user in parallel
            var result: [String: [UserLocationAssignment]] = [:]
            try await withThrowingTaskGroup(of: (String, [UserLocationAssignment]).self) { group in
                for user in users {
                    group.addTask {
                        let list = try await self.repo.fetchUserLocations(userId: user.id)
                        return (user.id, list)
                    }
                }
                for try await (uid, list) in group {
                    result[uid] = list
                }
            }
            assignments = result
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    public func toggle(userId: String, locationId: String, on: Bool) async {
        isSaving = true
        defer { isSaving = false }
        do {
            if on {
                try await repo.assignUserLocation(userId: userId, locationId: locationId, isPrimary: false)
                // Optimistic: synthesise an assignment locally
                let loc = locations.first(where: { $0.id == locationId })
                if let loc {
                    let newAssignment = UserLocationAssignment(
                        userId: userId,
                        location: loc,
                        isPrimary: false,
                        roleAtLocation: nil,
                        assignedAt: ISO8601DateFormatter().string(from: Date())
                    )
                    assignments[userId] = (assignments[userId] ?? []) + [newAssignment]
                }
            } else {
                try await repo.removeUserLocation(userId: userId, locationId: locationId)
                // Optimistic: remove from local state
                assignments[userId] = assignments[userId]?.filter { $0.location.id != locationId }
            }
        } catch {
            errorMessage = error.localizedDescription
            // Reload to restore truth
            await load()
        }
    }

    public func clearError() {
        errorMessage = nil
    }
}
