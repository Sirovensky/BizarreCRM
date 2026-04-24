import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EmployeeDetailView
//
// Full-detail screen for a single employee.
// iPad: rendered in the NavigationSplitView detail column.
// iPhone: pushed onto the NavigationStack from EmployeeListView.
//
// Displays:
//   • Profile header (name, role, active badge)
//   • Current shift card (if clocked in)
//   • Performance section (tickets, revenue, avg repair time)
//   • Commission summary (30-record rolling window)
//   • Admin actions: assign role, deactivate / reactivate

public struct EmployeeDetailView: View {

    @State private var vm: EmployeeDetailViewModel
    private let displayName: String

    public init(employeeId: Int64, displayName: String, api: APIClient) {
        self.displayName = displayName
        _vm = State(wrappedValue: EmployeeDetailViewModel(employeeId: employeeId, api: api))
    }

    // Internal init for test injection.
    init(viewModel: EmployeeDetailViewModel) {
        self.displayName = viewModel.detail?.displayName ?? "Employee"
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(vm.detail?.displayName ?? displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .confirmationDialog(
            "Assign Role",
            isPresented: $vm.showRoleConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm", role: .none) {
                Task { await vm.confirmRoleChange() }
            }
            Button("Cancel", role: .cancel) {
                vm.pendingRoleId = nil
            }
        } message: {
            if let roleId = vm.pendingRoleId,
               let role = vm.availableRoles.first(where: { $0.id == roleId }) {
                Text("Assign the role \"\(role.name)\" to \(vm.detail?.displayName ?? "this employee")?")
            }
        }
        .confirmationDialog(
            "Deactivate Employee",
            isPresented: $vm.showDeactivateConfirm,
            titleVisibility: .visible
        ) {
            Button("Deactivate", role: .destructive) {
                Task { await vm.confirmDeactivate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deactivating \(vm.detail?.displayName ?? "this employee") will prevent them from logging in.")
        }
        .confirmationDialog(
            "Reactivate Employee",
            isPresented: $vm.showReactivateConfirm,
            titleVisibility: .visible
        ) {
            Button("Reactivate", role: .none) {
                Task { await vm.confirmReactivate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reactivate \(vm.detail?.displayName ?? "this employee") so they can log in again?")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch vm.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load employee")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                LazyVStack(spacing: BrandSpacing.md, pinnedViews: []) {
                    profileCard
                    if vm.currentShift != nil {
                        currentShiftCard
                    }
                    performanceCard
                    commissionCard
                    adminActionsCard
                }
                .padding(BrandSpacing.md)
            }
        }
    }

    // MARK: - Profile card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.md) {
                ZStack {
                    Circle().fill(Color.bizarreOrangeContainer)
                    Text(vm.detail.map { initials($0) } ?? "")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.bizarreOnOrange)
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(vm.detail?.displayName ?? displayName)
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let role = vm.detail?.role, !role.isEmpty {
                        Text(role.capitalized)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    HStack(spacing: BrandSpacing.xs) {
                        Circle()
                            .fill(vm.isActive ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(vm.isActive ? "Active" : "Inactive")
                            .font(.brandLabelSmall())
                            .foregroundStyle(vm.isActive ? .green : .bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
            }

            if let email = vm.detail?.email, !email.isEmpty {
                Label(email, systemImage: "envelope")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
                    .accessibilityLabel("Email: \(email)")
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Current shift card

    @ViewBuilder
    private var currentShiftCard: some View {
        if let shift = vm.currentShift {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Label("Currently Clocked In", systemImage: "clock.fill")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.green)

                let elapsed = elapsedSince(shift.clockIn)
                Text(elapsed)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Elapsed time: \(elapsed)")

                Text("Since \(formattedTime(shift.clockIn))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Performance card

    @ViewBuilder
    private var performanceCard: some View {
        if let perf = vm.performance {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Performance")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)

                HStack(spacing: BrandSpacing.sm) {
                    StatCell(
                        title: "Tickets",
                        value: "\(perf.totalTickets)",
                        sub: "\(perf.closedTickets) closed",
                        icon: "ticket"
                    )
                    StatCell(
                        title: "Revenue",
                        value: formatted(currency: perf.totalRevenue),
                        sub: "\(formatted(currency: perf.avgTicketValue)) avg",
                        icon: "dollarsign.circle"
                    )
                    if let avgHours = perf.avgRepairHours {
                        StatCell(
                            title: "Avg Repair",
                            value: String(format: "%.1fh", avgHours),
                            sub: "\(perf.totalDevicesRepaired) devices",
                            icon: "wrench.and.screwdriver"
                        )
                    }
                }
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Commission summary card

    private var commissionCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Recent Commissions", systemImage: "percent")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(vm.formattedCommissionTotal)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Last 30 records")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.bizarreOrange.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent commissions: \(vm.formattedCommissionTotal) across last 30 records")
    }

    // MARK: - Admin actions card

    @ViewBuilder
    private var adminActionsCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Admin Actions")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            // Role picker
            if !vm.availableRoles.isEmpty {
                rolePicker
            }

            Divider()

            // Deactivate / reactivate
            if vm.isActive {
                Button(role: .destructive) {
                    vm.showDeactivateConfirm = true
                } label: {
                    Label("Deactivate Employee", systemImage: "person.crop.circle.badge.minus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("Deactivate this employee")
            } else {
                Button {
                    vm.showReactivateConfirm = true
                } label: {
                    Label("Reactivate Employee", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.green)
                }
                .accessibilityLabel("Reactivate this employee")
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .disabled(vm.actionState == .loading)
        .overlay(alignment: .topTrailing) {
            if vm.actionState == .loading {
                ProgressView()
                    .padding(BrandSpacing.sm)
            }
        }
    }

    @ViewBuilder
    private var rolePicker: some View {
        let currentRoleName = vm.detail?.role ?? ""
        let currentRole = vm.availableRoles.first { $0.name == currentRoleName }

        HStack {
            Label("Role", systemImage: "person.badge.key")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Menu {
                ForEach(vm.availableRoles) { role in
                    Button {
                        vm.requestRoleChange(roleId: role.id)
                    } label: {
                        if role.id == currentRole?.id {
                            Label(role.name.capitalized, systemImage: "checkmark")
                        } else {
                            Text(role.name.capitalized)
                        }
                    }
                }
            } label: {
                HStack(spacing: BrandSpacing.xs) {
                    Text(currentRoleName.isEmpty ? "None" : currentRoleName.capitalized)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .accessibilityLabel("Change role, currently \(currentRoleName.isEmpty ? "none" : currentRoleName)")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if vm.actionState == .loading {
            ToolbarItem(placement: .automatic) {
                ProgressView()
            }
        }
        if case .failed(let msg) = vm.actionState {
            ToolbarItem(placement: .automatic) {
                Label(msg, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    private func initials(_ d: EmployeeDetail) -> String {
        let f = d.firstName?.prefix(1).uppercased() ?? ""
        let l = d.lastName?.prefix(1).uppercased() ?? ""
        let c = f + l
        return c.isEmpty ? String((d.username ?? "?").prefix(2).uppercased()) : c
    }

    private func elapsedSince(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "—" }
        let secs = Int(Date().timeIntervalSince(date))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    private func formattedTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.timeStyle = .short
        display.dateStyle = .none
        return display.string(from: date)
    }

    private func formatted(currency value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - StatCell

private struct StatCell: View {
    let title: String
    let value: String
    let sub: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Label(title, systemImage: icon)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value), \(sub)")
    }
}
