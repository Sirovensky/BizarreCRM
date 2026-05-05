import SwiftUI
import Core
import DesignSystem

/// Full tenant-switcher screen.
///
/// - **iPhone**: pushed onto a `NavigationStack` (e.g. from Settings → Account → Switch Tenant).
/// - **iPad**: presented as a `.sheet` centered at 520 pt wide.
///
/// Usage from Settings:
/// ```swift
/// NavigationLink("Switch Tenant") {
///     TenantSwitcherView(viewModel: TenantSwitcherViewModel(store: tenantStore))
/// }
/// // or on iPad:
/// .sheet(isPresented: $showSwitcher) {
///     TenantSwitcherView(viewModel: vm)
///         .frame(width: 520)
/// }
/// ```
public struct TenantSwitcherView: View {
    @State private var vm: TenantSwitcherViewModel

    public init(viewModel: TenantSwitcherViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                loadingBody
            case .loaded(let tenants):
                loadedBody(tenants: tenants)
            case .switching:
                switchingBody
            case .failed(let msg):
                errorBody(message: msg)
            }
        }
        .navigationTitle("Switch Tenant")
#if canImport(UIKit)
        .navigationBarTitleDisplayMode(.large)
#endif
        .task { await vm.loadIfNeeded() }
        .alert(confirmAlertTitle, isPresented: $vm.showConfirmation) {
            Button("Switch", role: .none) {
                Task { await vm.confirmSwitch() }
            }
            Button("Cancel", role: .cancel) {
                vm.cancelSwitch()
            }
        } message: {
            if let name = vm.pendingTenant?.name {
                Text("Your active tenant will change to \(name). Cached data will refresh.")
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var loadingBody: some View {
        ProgressView("Loading tenants…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading tenant list")
    }

    @ViewBuilder
    private func loadedBody(tenants: [Tenant]) -> some View {
        List {
            Section {
                ForEach(tenants) { tenant in
                    TenantRow(
                        tenant: tenant,
                        isActive: tenant.id == activeTenantIdSync
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard tenant.id != activeTenantIdSync else { return }
                        vm.requestSwitch(to: tenant)
                    }
                    .accessibilityLabel(accessibilityLabel(for: tenant))
                    .accessibilityHint(tenant.id == activeTenantIdSync ? "Currently active" : "Double-tap to switch")
                }
            } header: {
                Text("Your Workspaces")
                    .font(.brandLabelSmall())
            }
        }
#if canImport(UIKit)
        .listStyle(.insetGrouped)
#endif
        .refreshable { await vm.reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") { Task { await vm.reload() } }
                    .accessibilityLabel("Refresh tenant list")
            }
        }
    }

    @ViewBuilder
    private var switchingBody: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Switching tenant…")
                .font(.brandBodyMedium())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Switching tenant, please wait")
    }

    @ViewBuilder
    private func errorBody(message: String) -> some View {
        ContentUnavailableView(
            "Could Not Load Tenants",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Retry") { Task { await vm.reload() } }
            }
        }
    }

    // MARK: - Helpers

    private var activeTenantIdSync: String? {
        if case .loaded(let tenants) = vm.state {
            return tenants.first?.id
        }
        return nil
    }

    private var confirmAlertTitle: String {
        if let name = vm.pendingTenant?.name {
            return "Switch to \(name)?"
        }
        return "Switch Tenant?"
    }

    private func accessibilityLabel(for tenant: Tenant) -> String {
        var parts: [String] = ["Tenant \(tenant.name)", "role \(tenant.role)"]
        if let date = tenant.lastAccessedAt {
            let formatted = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
            parts.append("last accessed \(formatted)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - TenantRow

private struct TenantRow: View {
    let tenant: Tenant
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            logoView
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(tenant.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.primary)
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(tenant.role.capitalized)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.secondary)
                    if let date = tenant.lastAccessedAt {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(date, style: .relative)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Active tenant")
#if canImport(UIKit)
                    .symbolEffect(.bounce, value: isActive)
#endif
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .contentShape(Rectangle())
#if canImport(UIKit)
        .if(!isActive) { view in view.hoverEffect(.highlight) }
#endif
    }

    @ViewBuilder
    private var logoView: some View {
        if let url = tenant.logoUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                default:
                    placeholderLogo
                }
            }
        } else {
            placeholderLogo
        }
    }

    private var placeholderLogo: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 40, height: 40)
            .overlay {
                Text(String(tenant.name.prefix(1)).uppercased())
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.accentColor)
            }
    }
}

// MARK: - View.if helper (local, no global pollution)

private extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}
