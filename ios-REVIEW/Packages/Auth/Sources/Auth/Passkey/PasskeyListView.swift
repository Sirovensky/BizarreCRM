#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PasskeyListView
//
// Settings → Security → "Passkeys"
// Shows enrolled credentials, allows revocation and new enrollment.
// iPhone: full-screen NavigationStack list.
// iPad: NavigationSplitView detail pane (ambient container handles split).

public struct PasskeyListView: View {
    @State private var vm: PasskeyViewModel
    @State private var showingRegisterFlow: Bool = false
    @State private var credentialToRevoke: PasskeyCredential?
    @State private var showRevokeConfirm: Bool = false

    private let username: String
    private let displayName: String

    public init(viewModel: PasskeyViewModel, username: String, displayName: String) {
        self._vm = State(wrappedValue: viewModel)
        self.username = username
        self.displayName = displayName
    }

    public var body: some View {
        Group {
            if vm.isLoadingCredentials && vm.credentials.isEmpty {
                loadingView
            } else if vm.credentials.isEmpty {
                emptyView
            } else {
                credentialList
            }
        }
        .navigationTitle("Passkeys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingRegisterFlow) {
            Task { await vm.loadCredentials() }
        } content: {
            PasskeyRegisterFlow(viewModel: vm, username: username, displayName: displayName)
        }
        .alert(
            "Revoke Passkey?",
            isPresented: $showRevokeConfirm,
            presenting: credentialToRevoke
        ) { credential in
            Button("Revoke", role: .destructive) {
                Task { await vm.deleteCredential(id: credential.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { credential in
            Text("\"\(credential.nickname)\" will be removed. You can add it back later.")
        }
        .task { await vm.loadCredentials() }
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
            Text("Loading passkeys…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("passkeys.loading")
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Passkeys", systemImage: "person.badge.key")
        } description: {
            Text("Add a passkey to sign in with Face ID or Touch ID — no password needed.")
        } actions: {
            Button {
                showingRegisterFlow = true
            } label: {
                Label("Add Passkey", systemImage: "plus")
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("passkeys.emptyAddButton")
        }
        .accessibilityIdentifier("passkeys.emptyState")
    }

    private var credentialList: some View {
        List {
            Section {
                ForEach(vm.credentials) { credential in
                    PasskeyRowView(credential: credential) {
                        credentialToRevoke = credential
                        showRevokeConfirm = true
                    }
                    .accessibilityIdentifier("passkey.row.\(credential.id)")
                }
            } header: {
                Text("Enrolled Devices")
                    .font(.brandLabelSmall())
            } footer: {
                Text("Passkeys sync across your Apple devices via iCloud Keychain.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if case .failed(let err) = vm.state {
                Section {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                        Text(err.localizedDescription ?? "An error occurred")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                    .accessibilityIdentifier("passkeys.error")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.loadCredentials() }
        .accessibilityIdentifier("passkeys.list")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingRegisterFlow = true
            } label: {
                Label("Add Passkey", systemImage: "plus")
            }
            .brandGlass(.regular, in: Capsule(), interactive: true)
            .accessibilityLabel("Register new passkey")
            .accessibilityIdentifier("passkeys.addButton")
        }
    }
}

// MARK: - PasskeyRowView

private struct PasskeyRowView: View {
    let credential: PasskeyCredential
    let onRevoke: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Device type icon
            Image(systemName: deviceIcon)
                .font(.title2)
                .foregroundStyle(.bizarreTeal)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(credential.nickname)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)

                Text("Added \(Self.dateFormatter.string(from: credential.createdAt))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                if let lastUsed = credential.lastUsedAt {
                    Text("Last used \(Self.dateFormatter.string(from: lastUsed))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .frame(minHeight: 60)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onRevoke) {
                Label("Revoke", systemImage: "trash")
            }
            .accessibilityIdentifier("passkey.revoke.\(credential.id)")
        }
        .contextMenu {
            Button(role: .destructive, action: onRevoke) {
                Label("Revoke Passkey", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Swipe left or use the context menu to revoke")
        // iPad hover effect
        .hoverEffect(.highlight)
    }

    private var deviceIcon: String {
        switch credential.deviceType?.lowercased() {
        case "iphone": return "iphone"
        case "ipad":   return "ipad"
        case "mac":    return "laptopcomputer"
        default:       return "key.fill"
        }
    }

    private var accessibilityLabel: String {
        var parts = [credential.nickname]
        parts.append("Added \(Self.dateFormatter.string(from: credential.createdAt))")
        if let last = credential.lastUsedAt {
            parts.append("Last used \(Self.dateFormatter.string(from: last))")
        }
        return parts.joined(separator: ", ")
    }
}
#endif
