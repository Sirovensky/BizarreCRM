import SwiftUI
import Core
import DesignSystem

/// §22 — iPad detail column: metadata inspector + diff renderer.
///
/// Shows the full audit entry detail (actor, event info, timestamps) and
/// below that a pretty-printed key-value table for the `metadata` dict.
/// When the metadata has `before`/`after` keys the AuditDiffRenderer is used
/// to produce colour-coded added/removed/unchanged rows.
///
/// Scrubbed fields (values equal to `"[scrubbed]"`) are rendered with a
/// distinct muted badge so the user knows data was intentionally redacted
/// (SCAN-506 compliance).
///
/// Liquid Glass is applied to the actor header card and the section chrome,
/// not to the individual data rows.
public struct AuditMetadataDiffInspector: View {

    private let entry: AuditLogEntry
    private let navigateToEntity: ((_ entityType: String, _ entityId: String) -> Void)?

    @State private var isDiffExpanded = true
    @State private var isMetaExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public init(
        entry: AuditLogEntry,
        navigateToEntity: ((_ entityType: String, _ entityId: String) -> Void)? = nil
    ) {
        self.entry = entry
        self.navigateToEntity = navigateToEntity
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                actorCard
                eventGrid
                metadataPanel
                if navigateToEntity != nil, entry.entityId != nil {
                    openEntityButton
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle(entry.action)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("ipad.auditlog.inspector.\(entry.id)")
    }

    // MARK: - Actor card

    private var actorCard: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ActorAvatar(name: entry.actorName, diameter: 52)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(entry.actorName)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                if let uid = entry.actorUserId {
                    Text("User ID \(uid)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                }
                Text(entry.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Actor: \(entry.actorName)")
    }

    // MARK: - Event grid

    private var eventGrid: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            sectionHeader("Event", systemImage: "bolt.circle")

            Grid(alignment: .leading,
                 horizontalSpacing: DesignTokens.Spacing.lg,
                 verticalSpacing: DesignTokens.Spacing.sm) {
                gridRow(label: "Action") {
                    Text(entry.action)
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOrange)
                        .textSelection(.enabled)
                }
                gridRow(label: "Entity") {
                    let label = entry.entityId.map { "\(entry.entityKind) #\($0)" } ?? entry.entityKind
                    Text(label)
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                }
                if let entityId = entry.entityId {
                    gridRow(label: "Entity ID") {
                        Text(String(entityId))
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurface)
                            .textSelection(.enabled)
                    }
                }
                gridRow(label: "Log ID") {
                    Text(entry.id)
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Metadata panel

    @ViewBuilder
    private var metadataPanel: some View {
        if let meta = entry.metadata, !meta.isEmpty {
            // Check for before/after diff structure
            if let beforeVal = meta["before"], let afterVal = meta["after"],
               case .object(let beforeDict) = beforeVal,
               case .object(let afterDict) = afterVal {
                diffPanel(
                    before: beforeDict,
                    after: afterDict,
                    rest: meta.filter { $0.key != "before" && $0.key != "after" }
                )
            } else {
                flatMetadataPanel(meta)
            }
        } else {
            emptyMetadataPanel
        }
    }

    // MARK: Diff panel (before/after)

    private func diffPanel(
        before: [String: AuditDiffValue],
        after: [String: AuditDiffValue],
        rest: [String: AuditDiffValue]
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            disclosureHeader(
                title: "Changes",
                systemImage: "arrow.left.arrow.right",
                isExpanded: $isDiffExpanded
            )

            if isDiffExpanded {
                let diff = AuditDiff(before: before, after: after)
                let lines = AuditDiffRenderer.render(diff)

                if lines.isEmpty {
                    Text("No field changes recorded.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                } else {
                    VStack(spacing: 0) {
                        ForEach(lines) { line in
                            DiffLineRow(line: line, colorScheme: colorScheme)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                }

                // Any extra metadata keys beyond before/after
                if !rest.isEmpty {
                    Divider()
                        .padding(.vertical, DesignTokens.Spacing.xs)
                    flatKeyValueRows(rest)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: Flat metadata panel

    private func flatMetadataPanel(_ meta: [String: AuditDiffValue]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            disclosureHeader(
                title: "Details",
                systemImage: "doc.text.magnifyingglass",
                isExpanded: $isMetaExpanded
            )

            if isMetaExpanded {
                flatKeyValueRows(meta)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var emptyMetadataPanel: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No additional details")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: Flat key-value rows

    @ViewBuilder
    private func flatKeyValueRows(_ meta: [String: AuditDiffValue]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(meta.keys.sorted(), id: \.self) { key in
                MetadataKVRow(key: key, value: meta[key] ?? .null)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    // MARK: - Open entity button

    private var openEntityButton: some View {
        Button {
            guard let eid = entry.entityId else { return }
            navigateToEntity?(entry.entityKind, String(eid))
        } label: {
            Label("Open \(entry.entityKind.capitalized)", systemImage: "arrow.right.circle")
                .font(.brandBodyMedium())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .accessibilityIdentifier("ipad.auditlog.openEntity.\(entry.id)")
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(title)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
        }
    }

    private func disclosureHeader(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.quick)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                sectionHeader(title, systemImage: systemImage)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded.wrappedValue ? "Collapse \(title)" : "Expand \(title)")
    }

    private func gridRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            content()
        }
    }
}

// MARK: - MetadataKVRow

/// One key-value row in the flat metadata table.
/// Renders scrubbed values (`"[scrubbed]"`) with a distinct muted badge.
private struct MetadataKVRow: View {
    let key: String
    let value: AuditDiffValue

    private var isScrubbed: Bool {
        if case .string(let s) = value { return s == "[scrubbed]" }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Text("\(key):")
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(minWidth: 80, alignment: .leading)
                .lineLimit(1)

            if isScrubbed {
                scrubbedBadge
            } else {
                Text(value.displayString)
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .lineLimit(6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityLabel(isScrubbed ? "\(key): redacted" : "\(key): \(value.displayString)")
        .accessibilityIdentifier("metadata.row.\(key)")
    }

    private var scrubbedBadge: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: "eye.slash")
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text("redacted")
                .font(.brandLabelSmall())
        }
        .foregroundStyle(.bizarreOnSurfaceMuted)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(Color.bizarreSurface1.opacity(0.6), in: Capsule())
        .accessibilityLabel("redacted value")
    }
}

// MARK: - DiffLineRow

/// One coloured row in the before/after diff table.
private struct DiffLineRow: View {
    let line: DiffLine
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
            Text(prefix)
                .font(.brandMono(size: 12))
                .foregroundStyle(AuditDiffRenderer.color(for: line.kind, colorScheme: colorScheme))
                .frame(width: 12)
                .accessibilityHidden(true)

            Text("\(line.key):")
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(minWidth: 80, alignment: .leading)
                .lineLimit(1)

            Text(line.value)
                .font(.brandMono(size: 12))
                .foregroundStyle(AuditDiffRenderer.color(for: line.kind, colorScheme: colorScheme))
                .textSelection(.enabled)
                .lineLimit(6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(AuditDiffRenderer.backgroundColor(for: line.kind))
        .accessibilityLabel(a11yLabel)
        .accessibilityIdentifier("diff.line.\(line.id)")
    }

    private var prefix: String {
        switch line.kind {
        case .added:     return "+"
        case .removed:   return "-"
        case .unchanged: return " "
        }
    }

    private var a11yLabel: String {
        switch line.kind {
        case .added:     return "Added \(line.key): \(line.value)"
        case .removed:   return "Removed \(line.key): \(line.value)"
        case .unchanged: return "\(line.key): \(line.value)"
        }
    }
}
