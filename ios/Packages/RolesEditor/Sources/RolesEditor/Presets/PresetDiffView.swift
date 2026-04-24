import SwiftUI
import DesignSystem

// MARK: - PresetDiffView
//
// §47 Roles Capability Presets — shows which capabilities will be added or
// removed relative to a role's current state when a preset is applied.
// Pure display view; no async work, no side effects.

/// Displays a diff of capability changes that applying a preset would produce.
///
/// - Shows a green "Added" section for capabilities the preset grants.
/// - Shows a red "Removed" section for capabilities the preset strips.
/// - Shows a neutral "No changes" message when the diff is empty.
public struct PresetDiffView: View {

    // MARK: Input

    public let diff: PresetCapabilityDiff
    public let presetName: String

    // MARK: Init

    public init(diff: PresetCapabilityDiff, presetName: String) {
        self.diff = diff
        self.presetName = presetName
    }

    // MARK: Body

    public var body: some View {
        if diff.isEmpty {
            noChangesRow
        } else {
            addedSection
            removedSection
        }
    }

    // MARK: - No-changes

    @ViewBuilder
    private var noChangesRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Current capabilities already match \"\(presetName)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No changes — current capabilities already match \(presetName)")
    }

    // MARK: - Added

    @ViewBuilder
    private var addedSection: some View {
        if !diff.added.isEmpty {
            Section {
                ForEach(diff.sortedAdded, id: \.self) { capId in
                    DiffRow(capabilityId: capId, kind: .added)
                }
            } header: {
                diffSectionHeader(
                    title: "\(diff.added.count) Added",
                    color: .green,
                    icon: "plus.circle.fill"
                )
            }
        }
    }

    // MARK: - Removed

    @ViewBuilder
    private var removedSection: some View {
        if !diff.removed.isEmpty {
            Section {
                ForEach(diff.sortedRemoved, id: \.self) { capId in
                    DiffRow(capabilityId: capId, kind: .removed)
                }
            } header: {
                diffSectionHeader(
                    title: "\(diff.removed.count) Removed",
                    color: .red,
                    icon: "minus.circle.fill"
                )
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func diffSectionHeader(title: String, color: Color, icon: String) -> some View {
        Label(title, systemImage: icon)
            .foregroundStyle(color)
            .font(.footnote.weight(.semibold))
            .textCase(nil)
    }
}

// MARK: - DiffRow

/// A single capability row inside the diff view.
private struct DiffRow: View {

    enum Kind { case added, removed }

    let capabilityId: String
    let kind: Kind

    private var capability: Capability? { CapabilityCatalog.capability(for: capabilityId) }

    private var iconName: String {
        kind == .added ? "plus.circle.fill" : "minus.circle.fill"
    }

    private var iconColor: Color {
        kind == .added ? .green : .red
    }

    private var accessibilitySuffix: String {
        kind == .added ? "will be added" : "will be removed"
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.subheadline)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(capability?.label ?? capabilityId)
                    .font(.subheadline)
                if let desc = capability?.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(capability?.label ?? capabilityId) — \(accessibilitySuffix)")
    }
}
