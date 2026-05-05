import SwiftUI
import Core
import DesignSystem

/// Compact half-sheet tenant picker shown during the login flow when a user
/// belongs to 2+ tenants.
///
/// Present this immediately after successful password authentication:
/// ```swift
/// .sheet(isPresented: $showPicker) {
///     TenantPickerSheet(viewModel: vm) {
///         loginFlow.step = .done
///     }
/// }
/// ```
///
/// On iPad the sheet is compact by default via `.presentationDetents`.
public struct TenantPickerSheet: View {
    @State private var vm: TenantSwitcherViewModel
    private let onComplete: @MainActor () -> Void

    public init(viewModel: TenantSwitcherViewModel, onComplete: @escaping @MainActor () -> Void) {
        _vm = State(initialValue: viewModel)
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Choose Workspace")
#if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        EmptyView()
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DesignTokens.Radius.xl)
        .task { await vm.loadIfNeeded() }
        .alert(confirmAlertTitle, isPresented: $vm.showConfirmation) {
            Button("Continue", role: .none) {
                Task {
                    await vm.confirmSwitch()
                    onComplete()
                }
            }
            Button("Cancel", role: .cancel) { vm.cancelSwitch() }
        } message: {
            if let name = vm.pendingTenant?.name {
                Text("You'll be signed into \(name).")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .loading:
            ProgressView("Loading workspaces…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading workspace list")

        case .loaded(let tenants):
            List(tenants) { tenant in
                CompactTenantRow(tenant: tenant)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.requestSwitch(to: tenant) }
                    .accessibilityLabel("Workspace \(tenant.name), role \(tenant.role)")
                    .accessibilityHint("Double-tap to continue as \(tenant.name)")
            }
#if canImport(UIKit)
            .listStyle(.insetGrouped)
#endif

        case .switching:
            VStack(spacing: DesignTokens.Spacing.lg) {
                ProgressView()
                Text("Signing in…")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Signing into workspace, please wait")

        case .failed(let msg):
            ContentUnavailableView(
                "Could Not Load Workspaces",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        }
    }

    private var confirmAlertTitle: String {
        if let name = vm.pendingTenant?.name {
            return "Sign in as \(name)?"
        }
        return "Switch Workspace?"
    }
}

// MARK: - CompactTenantRow

private struct CompactTenantRow: View {
    let tenant: Tenant

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Logo placeholder
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(tenant.name.prefix(1)).uppercased())
                        .font(.brandLabelLarge())
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(tenant.name)
                    .font(.brandBodyMedium())
                Text(tenant.role.capitalized)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
#if canImport(UIKit)
        .hoverEffect(.highlight)
#endif
    }
}
