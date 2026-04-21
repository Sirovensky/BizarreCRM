import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

@MainActor
@Observable
public final class EmployeeListViewModel {
    public private(set) var items: [Employee] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// Exposed for `StalenessIndicator` chip in toolbar.
    public private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cachedRepo: EmployeeCachedRepository?

    public init(api: APIClient, cachedRepo: EmployeeCachedRepository? = nil) {
        self.api = api
        self.cachedRepo = cachedRepo
    }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                items = try await repo.listEmployees()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                items = try await api.listEmployees()
            }
        } catch {
            AppLog.ui.error("Employees load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func forceRefresh() async {
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                items = try await repo.forceRefresh()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                items = try await api.listEmployees()
            }
        } catch {
            AppLog.ui.error("Employees force-refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct EmployeeListView: View {
    @State private var vm: EmployeeListViewModel

    public init(api: APIClient, cachedRepo: EmployeeCachedRepository? = nil) {
        _vm = State(wrappedValue: EmployeeListViewModel(api: api, cachedRepo: cachedRepo))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Employees")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.forceRefresh() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load employees").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "employees")
        } else if vm.items.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.3")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No employees").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.items) { emp in
                    Row(employee: emp).listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private struct Row: View {
        let employee: Employee

        var body: some View {
            HStack(spacing: BrandSpacing.md) {
                ZStack {
                    Circle().fill(Color.bizarreOrangeContainer)
                    Text(employee.initials)
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnOrange)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(employee.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    if let role = employee.role, !role.isEmpty {
                        Text(role.capitalized)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let email = employee.email, !email.isEmpty {
                        Text(email)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if !employee.active {
                    Text("Inactive")
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .background(Color.bizarreSurface2, in: Capsule())
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: employee))
        }

        static func a11y(for emp: Employee) -> String {
            var parts: [String] = [emp.displayName]
            if let role = emp.role, !role.isEmpty { parts.append(role.capitalized) }
            if !emp.active { parts.append("Inactive") }
            return parts.joined(separator: ". ")
        }
    }
}
