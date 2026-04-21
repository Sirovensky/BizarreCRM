import SwiftUI
import Core
import DesignSystem

// MARK: - FeatureFlagsView

/// Lists all known `FeatureFlag` cases with local override toggles.
/// Admin-only. Shows server value (read-only) + local override + reset button.
public struct FeatureFlagsView: View {

    private let manager: FeatureFlagManager

    @State private var searchQuery: String = ""
    @State private var overrideStates: [FeatureFlag: Bool] = [:]
    @State private var showResetAllConfirm: Bool = false

    public init(manager: FeatureFlagManager = .shared) {
        self.manager = manager
    }

    // MARK: - Filtered flags

    private var filteredFlags: [FeatureFlag] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return FeatureFlag.allCases }
        return FeatureFlag.allCases.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.rawValue.lowercased().contains(q)
        }
    }

    // MARK: - Body

    public var body: some View {
        List {
            searchSection
            ForEach(filteredFlags, id: \.self) { flag in
                FlagRow(
                    flag: flag,
                    manager: manager,
                    overrideStates: $overrideStates
                )
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Feature Flags")
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Reset all overrides?",
            isPresented: $showResetAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset all", role: .destructive) {
                manager.clearAllOverrides()
                overrideStates = [:]
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All local overrides will be removed. Server and default values will apply.")
        }
        .onAppear { refreshOverrideStates() }
    }

    // MARK: - Sections

    private var searchSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("Filter flags", text: $searchQuery)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Filter feature flags")
                    .accessibilityIdentifier("featureFlags.search")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Reset All") { showResetAllConfirm = true }
                .foregroundStyle(.bizarreError)
                .accessibilityLabel("Reset all feature flag overrides")
                .accessibilityIdentifier("featureFlags.resetAll")
        }
    }

    // MARK: - Helpers

    private func refreshOverrideStates() {
        for flag in FeatureFlag.allCases {
            if let override = manager.localOverride(for: flag) {
                overrideStates[flag] = override
            }
        }
    }
}

// MARK: - FlagRow

private struct FlagRow: View {
    let flag: FeatureFlag
    let manager: FeatureFlagManager
    @Binding var overrideStates: [FeatureFlag: Bool]

    private var effectiveValue: Bool { manager.isEnabled(flag) }
    private var serverValue: Bool? { manager.serverValue(for: flag) }
    private var hasOverride: Bool { manager.hasLocalOverride(for: flag) }
    private var localOverride: Bool? { manager.localOverride(for: flag) }

    // Binding for the toggle — reads/writes through FeatureFlagManager
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { localOverride ?? effectiveValue },
            set: { newValue in
                manager.setLocalOverride(flag, enabled: newValue)
                overrideStates[flag] = newValue
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(flag.displayName)
                        .font(.body)
                        .foregroundStyle(.bizarreOnSurface)

                    Text(flag.rawValue)
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                }

                Spacer()

                Toggle("", isOn: toggleBinding)
                    .labelsHidden()
                    .accessibilityLabel("\(flag.displayName) local override")
                    .accessibilityIdentifier("featureFlag.\(flag.rawValue).toggle")
            }

            HStack(spacing: BrandSpacing.sm) {
                serverValueBadge
                if hasOverride { overrideBadge }
            }

            if hasOverride {
                Button("Reset to default") {
                    manager.setLocalOverride(flag, enabled: nil)
                    overrideStates[flag] = nil
                }
                .font(.caption)
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Reset \(flag.displayName) to server default")
                .accessibilityIdentifier("featureFlag.\(flag.rawValue).reset")
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .contain)
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }

    @ViewBuilder
    private var serverValueBadge: some View {
        if let sv = serverValue {
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: sv ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption2)
                Text("Server: \(sv ? "on" : "off")")
                    .font(.caption2)
            }
            .foregroundStyle(sv ? Color.bizarreSuccess : Color.bizarreOnSurfaceMuted)
            .accessibilityLabel("Server value: \(sv ? "on" : "off")")
        } else {
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                Text("Server: unknown")
                    .font(.caption2)
            }
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityLabel("Server value: unknown")
        }
    }

    private var overrideBadge: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.caption2)
            Text("Local override")
                .font(.caption2)
        }
        .foregroundStyle(.bizarreWarning)
        .accessibilityLabel("Local override active")
    }
}
