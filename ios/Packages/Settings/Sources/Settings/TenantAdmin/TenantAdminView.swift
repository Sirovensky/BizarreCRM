import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - TenantAdminView

/// Admin-only panel showing tenant metadata, subscription status,
/// API usage stats, and access to user impersonation.
/// Only rendered when the current user has `owner` or `admin` role.
public struct TenantAdminView: View {

    @State private var vm: TenantAdminViewModel
    @State private var showImpersonateSheet: Bool = false

    // Stub user list for impersonation picker (real app fetches from `/users`)
    private let stubUsers: [UserRow] = [
        UserRow(id: "u1", displayName: "Alice Johnson", email: "alice@example.com"),
        UserRow(id: "u2", displayName: "Bob Smith", email: "bob@example.com"),
    ]

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: TenantAdminViewModel(api: api))
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.base) {
                adminHeader
                tenantInfoSection
                subscriptionSection
                usageSection
                actionsSection
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Tenant Admin")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .overlay {
            if vm.isLoadingTenant && vm.tenantInfo == nil {
                ProgressView("Loading…")
                    .accessibilityLabel("Loading tenant information")
            }
        }
        .sheet(isPresented: $showImpersonateSheet) {
            ImpersonateUserSheet(users: stubUsers) { userId, reason, pin in
                await vm.impersonate(userId: userId, reason: reason, managerPin: pin)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Sections

    private var adminHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Tenant Admin")
                    .font(.headline)
                    .foregroundStyle(.bizarreOnSurface)
                Text("Admin-only control panel")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var tenantInfoSection: some View {
        if let info = vm.tenantInfo {
            GroupBox("Tenant Info") {
                VStack(spacing: BrandSpacing.sm) {
                    infoRow(label: "Tenant ID", value: info.id, mono: true)
                    infoRow(label: "Slug", value: info.slug, mono: true)
                    infoRow(label: "Name", value: info.name)
                    infoRow(label: "Created", value: formatDate(info.createdAt))
                }
            }
            .groupBoxStyle(.brand)
        } else if let err = vm.errorMessage {
            GroupBox("Tenant Info") {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.bizarreError)
                    .font(.caption)
            }
            .groupBoxStyle(.brand)
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        if let info = vm.tenantInfo {
            GroupBox("Subscription") {
                VStack(spacing: BrandSpacing.sm) {
                    HStack {
                        Text("Plan")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text(info.plan.capitalized)
                            .fontWeight(.semibold)
                            .foregroundStyle(.bizarreOrange)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Plan: \(info.plan)")

                    HStack {
                        Text("Status")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text(info.isActive ? "Active" : "Inactive")
                            .foregroundStyle(info.isActive ? .bizarreSuccess : .bizarreError)
                            .fontWeight(.medium)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Status: \(info.isActive ? "Active" : "Inactive")")

                    if let renewal = info.planRenewalDate {
                        infoRow(label: "Renewal", value: formatDate(renewal))
                    }
                }
            }
            .groupBoxStyle(.brand)
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        GroupBox("API Usage") {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                if let stats = vm.usageStats {
                    HStack {
                        usageStat(label: "Today", value: "\(stats.requestsToday)")
                        Divider().frame(height: 40)
                        usageStat(label: "This Month", value: "\(stats.requestsThisMonth)")
                    }
                    .frame(maxWidth: .infinity)

                    APIUsageChart(dailyBuckets: stats.dailyBuckets)
                        .padding(.top, BrandSpacing.xs)
                } else if vm.isLoadingUsage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .accessibilityLabel("Loading API usage")
                } else {
                    Text("Usage data unavailable")
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .groupBoxStyle(.brand)
    }

    private var actionsSection: some View {
        GroupBox("Admin Actions") {
            VStack(spacing: BrandSpacing.sm) {
                Button {
                    showImpersonateSheet = true
                } label: {
                    Label("Impersonate User", systemImage: "person.fill.viewfinder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.brand)
                .accessibilityLabel("Impersonate a user — requires manager PIN and reason")
                .accessibilityHint("Opens a sheet to select a user to impersonate")
                .accessibilityIdentifier("tenantAdmin.impersonate")

                if let err = vm.impersonateError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        .groupBoxStyle(.brand)
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(mono ? .brandMono(size: 13) : .body)
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func usageStat(label: String, value: String) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.bizarreOnSurface)
            Text(label)
                .font(.caption)
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) requests")
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - GroupBox brand style

private struct BrandGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            configuration.label
                .font(.subheadline.bold())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            configuration.content
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }
}

private extension GroupBoxStyle where Self == BrandGroupBoxStyle {
    static var brand: BrandGroupBoxStyle { BrandGroupBoxStyle() }
}

// MARK: - Button brand style

private struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .background(
                Color.bizarreOrange.opacity(configuration.isPressed ? 0.25 : 0.15),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            )
            .foregroundStyle(.bizarreOrange)
            .animation(.easeInOut(duration: DesignTokens.Motion.quick), value: configuration.isPressed)
    }
}

private extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
}
