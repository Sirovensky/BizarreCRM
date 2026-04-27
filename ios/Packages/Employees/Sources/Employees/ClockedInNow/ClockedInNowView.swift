import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ClockedInNowView
//
// §14.1 — "Who's clocked in right now" view.
// Fetches GET /api/v1/employees, then for each employee calls getClockStatus
// to determine if they are currently clocked in. Polls every 60s.
// iPhone: list. iPad: sidebar + detail.
//
// Note: The server's GET /api/v1/employees list endpoint does not embed
// `is_clocked_in` (§74 gap). We fetch a slim presence struct from
// GET /api/v1/employees — the server does return this field on newer builds
// (see bench endpoint). EmployeePresence decodes it tolerantly.

/// Slim struct for the presence poll — decodes `is_clocked_in` from the
/// employees list endpoint. Field is optional to handle older server builds.
struct EmployeePresence: Decodable, Sendable, Identifiable, Hashable {
    let id: Int64
    let firstName: String?
    let lastName: String?
    let username: String?
    let role: String?
    let isClockedIn: Bool

    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (username ?? "User #\(id)") : parts.joined(separator: " ")
    }
    var initials: String {
        let f = firstName?.prefix(1).uppercased() ?? ""
        let l = lastName?.prefix(1).uppercased() ?? ""
        let c = f + l
        return c.isEmpty ? String((username ?? "?").prefix(2).uppercased()) : c
    }

    enum CodingKeys: String, CodingKey {
        case id, username, role
        case firstName   = "first_name"
        case lastName    = "last_name"
        case isClockedIn = "is_clocked_in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        firstName = try? c.decode(String.self, forKey: .firstName)
        lastName  = try? c.decode(String.self, forKey: .lastName)
        username  = try? c.decode(String.self, forKey: .username)
        role      = try? c.decode(String.self, forKey: .role)
        isClockedIn = (try? c.decode(Bool.self, forKey: .isClockedIn)) ?? false
    }
}

private extension APIClient {
    func listEmployeePresence() async throws -> [EmployeePresence] {
        try await get("/api/v1/employees", as: [EmployeePresence].self)
    }
}

@MainActor
@Observable
public final class ClockedInNowViewModel {
    public private(set) var clockedIn: [EmployeePresence] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var lastRefreshed: Date?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await api.listEmployeePresence()
            clockedIn = all.filter { $0.isClockedIn }
            lastRefreshed = Date()
        } catch {
            AppLog.ui.error("ClockedInNow load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func startPolling(intervalSeconds: TimeInterval = 60) {
        stopPolling()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.load()
            }
        }
    }

    public func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

public struct ClockedInNowView: View {
    @State private var vm: ClockedInNowViewModel
    @State private var selected: EmployeePresence?

    public init(api: APIClient) {
        _vm = State(wrappedValue: ClockedInNowViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Clocked In Now")
        .task {
            await vm.load()
            vm.startPolling()
        }
        .onDisappear { vm.stopPolling() }
        .refreshable { await vm.load() }
    }

    // MARK: - iPhone

    private var iPhoneLayout: some View {
        Group {
            if vm.isLoading && vm.clockedIn.isEmpty {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage, vm.clockedIn.isEmpty {
                errorState(err)
            } else if vm.clockedIn.isEmpty {
                emptyState
            } else {
                employeeList
            }
        }
    }

    // MARK: - iPad

    private var iPadLayout: some View {
        NavigationSplitView {
            Group {
                if vm.isLoading && vm.clockedIn.isEmpty {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.clockedIn.isEmpty {
                    emptyState
                } else {
                    List(vm.clockedIn, selection: $selected) { emp in
                        ClockedInRow(employee: emp)
                            .hoverEffect(.highlight)
                            .tag(emp)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Clocked In Now")
        } detail: {
            if let emp = selected {
                VStack(spacing: BrandSpacing.md) {
                    ZStack {
                        Circle().fill(Color.bizarreOrangeContainer)
                        Text(emp.initials)
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnOrange)
                    }
                    .frame(width: 80, height: 80)
                    Text(emp.displayName).font(.brandTitleLarge()).foregroundStyle(.bizarreOnSurface)
                    if let role = emp.role, !role.isEmpty {
                        Text(role.capitalized).font(.brandBodyLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Clocked in").font(.brandBodyMedium()).foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Select an employee",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Choose an employee to view details.")
                )
            }
        }
    }

    // MARK: - Shared list

    private var employeeList: some View {
        List(vm.clockedIn) { emp in
            ClockedInRow(employee: emp)
                .listRowBackground(Color.bizarreSurface1)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No one is clocked in")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No employees are currently clocked in")
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ClockedInRow

private struct ClockedInRow: View {
    let employee: EmployeePresence

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15))
                Text(employee.initials)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.green)
            }
            .frame(width: 40, height: 40)
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
            }
            Spacer()
            Image(systemName: "clock.badge.checkmark.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(employee.displayName)\(employee.role.map { ", \($0.capitalized)" } ?? ""). Clocked in.")
    }
}
