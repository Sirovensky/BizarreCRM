#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §41.7 Expiry policy admin editor

/// Admin settings screen: choose the tenant-wide default expiry for new
/// payment links (7d / 14d / 30d / never).
public struct PaymentLinkExpiryEditorView: View {
    @State private var vm: PaymentLinkExpiryEditorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient) {
        _vm = State(wrappedValue: PaymentLinkExpiryEditorViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            form
        }
        .navigationTitle("Link expiry policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    BrandHaptics.tap()
                    Task { await vm.save() }
                }
                .disabled(vm.isSaving)
                .accessibilityIdentifier("expiry.saveButton")
            }
        }
        .task { await vm.load() }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "Could not save expiry policy.")
        }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(PaymentLinkExpiryPolicy.allCases, id: \.self) { policy in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(policy.label)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            if let d = policy.days {
                                Text("Links expire \(d) days after creation")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            } else {
                                Text("Links never automatically expire")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        Spacer()
                        if vm.selected == policy {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityLabel("Selected")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { vm.selected = policy }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(vm.selected == policy ? .isSelected : [])
                }
                .listRowBackground(Color.bizarreSurface1)
            } header: {
                Text("Default expiry for new links")
            } footer: {
                Text("Applies to all new payment links. Existing links are not affected.")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if vm.isSaving {
                Section {
                    HStack {
                        ProgressView()
                        Text("Saving…")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PaymentLinkExpiryEditorViewModel {
    public var selected: PaymentLinkExpiryPolicy = .sevenDays
    public private(set) var isSaving: Bool = false
    public var showError: Bool = false
    public private(set) var errorMessage: String?

    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        do {
            let dto = try await api.getExpiryPolicy()
            selected = dto.defaultExpiryPolicy
        } catch {
            // First load may 404 — fall back to default 7d silently.
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await api.setExpiryPolicy(selected)
            BrandHaptics.success()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not save expiry policy."
            showError = true
        }
    }
}
#endif
