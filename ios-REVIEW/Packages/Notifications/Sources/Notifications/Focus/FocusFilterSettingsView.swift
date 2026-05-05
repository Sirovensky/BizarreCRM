import SwiftUI
import Observation
import DesignSystem

// MARK: - FocusFilterSettingsViewModel

@MainActor
@Observable
public final class FocusFilterSettingsViewModel {

    public private(set) var descriptor: FocusFilterDescriptor = .defaultDescriptor()
    public private(set) var isSaving: Bool = false
    public private(set) var error: String?

    private let endpoints: FocusFilterEndpoints?

    public init(endpoints: FocusFilterEndpoints? = nil) {
        self.endpoints = endpoints
    }

    // MARK: - Load

    public func load() async {
        guard let endpoints else { return }
        do {
            descriptor = try await endpoints.fetchDescriptor()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Edit

    public func updatePolicy(_ policy: FocusFilterPolicy) {
        descriptor = descriptor.updatingPolicy(policy)
    }

    // MARK: - Save

    public func save() async {
        guard let endpoints else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await endpoints.saveDescriptor(descriptor)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - FocusFilterSettingsView

/// Admin/user UI for configuring per-Focus notification policies.
/// "Work mode shows only critical (server down, manager PIN failures)."
public struct FocusFilterSettingsView: View {

    @State private var vm: FocusFilterSettingsViewModel
    @State private var editingMode: FocusMode?

    public init(viewModel: FocusFilterSettingsViewModel = FocusFilterSettingsViewModel()) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            list
        }
        .navigationTitle("Focus Filters")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { saveButton }
        .task { await vm.load() }
        .sheet(item: $editingMode) { mode in
            FocusPolicyEditorSheet(
                mode: mode,
                policy: vm.descriptor.policies[mode] ?? FocusFilterPolicy(
                    focusMode: mode,
                    allowedCategories: Set(EventCategory.allCases)
                )
            ) { updated in
                vm.updatePolicy(updated)
            }
        }
        .overlay(errorBanner)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        List {
            entitlementNote
            ForEach(FocusMode.allCases) { mode in
                modeRow(mode)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var entitlementNote: some View {
        Section {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.bizarreTeal)
                    .accessibilityHidden(true)
                Text("BizarreCRM cannot automatically detect your active Focus. Policies apply only when you are manually in that mode. To enable auto-detection, the \("`com.apple.developer.focus`") entitlement must be provisioned.")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.vertical, BrandSpacing.xs)
            .listRowBackground(Color.bizarreSurface1)
        }
    }

    @ViewBuilder
    private func modeRow(_ mode: FocusMode) -> some View {
        Button {
            editingMode = mode
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: mode.iconName)
                    .foregroundStyle(Color.bizarreOrange)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(mode.rawValue)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let policy = vm.descriptor.policies[mode] {
                        Text(policySummary(policy))
                            .font(.brandBodySmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else {
                        Text("No policy set — all notifications pass through")
                            .font(.brandBodySmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, BrandSpacing.xs)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityLabel("\(mode.rawValue) Focus policy")
        .accessibilityHint("Tap to edit notification policy for \(mode.rawValue) Focus")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var saveButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task { await vm.save() }
            } label: {
                if vm.isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save")
                }
            }
            .disabled(vm.isSaving)
            .accessibilityLabel(vm.isSaving ? "Saving…" : "Save Focus policies")
        }
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if let err = vm.error {
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.bizarreError)
                        .accessibilityHidden(true)
                    Text(err)
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                }
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                .padding(BrandSpacing.base)
            }
        }
    }

    // MARK: - Helpers

    private func policySummary(_ policy: FocusFilterPolicy) -> String {
        if policy.allowedCategories.isEmpty {
            return policy.allowCriticalOverride ? "Critical only" : "All suppressed"
        }
        let names = policy.allowedCategories.map(\.rawValue).sorted().joined(separator: ", ")
        return "Allows: \(names)"
    }
}

// MARK: - FocusPolicyEditorSheet

private struct FocusPolicyEditorSheet: View {

    let mode: FocusMode
    @State private var policy: FocusFilterPolicy
    let onSave: (FocusFilterPolicy) -> Void

    @Environment(\.dismiss) private var dismiss

    init(mode: FocusMode, policy: FocusFilterPolicy, onSave: @escaping (FocusFilterPolicy) -> Void) {
        self.mode = mode
        _policy = State(wrappedValue: policy)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Allowed Categories") {
                    ForEach(EventCategory.allCases, id: \.rawValue) { cat in
                        Toggle(cat.rawValue, isOn: Binding(
                            get: { policy.allowedCategories.contains(cat) },
                            set: { enabled in
                                var cats = policy.allowedCategories
                                if enabled { cats.insert(cat) } else { cats.remove(cat) }
                                policy = FocusFilterPolicy(
                                    focusMode: policy.focusMode,
                                    allowedCategories: cats,
                                    allowCriticalOverride: policy.allowCriticalOverride
                                )
                            }
                        ))
                        .tint(.bizarreOrange)
                        .listRowBackground(Color.bizarreSurface1)
                    }
                }

                Section {
                    Toggle("Allow critical alerts to override", isOn: Binding(
                        get: { policy.allowCriticalOverride },
                        set: { enabled in
                            policy = FocusFilterPolicy(
                                focusMode: policy.focusMode,
                                allowedCategories: policy.allowedCategories,
                                allowCriticalOverride: enabled
                            )
                        }
                    ))
                    .tint(.bizarreOrange)
                    .listRowBackground(Color.bizarreSurface1)
                } footer: {
                    Text("Critical alerts (backup failure, security events) always surface when this is on.")
                        .font(.brandBodySmall())
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle(mode.rawValue)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onSave(policy)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Font helpers

private extension Font {
    static func brandBodySmall() -> Font { .system(size: 13) }
    static func brandBodyLarge() -> Font { .system(size: 16) }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        FocusFilterSettingsView()
    }
}
#endif
