import SwiftUI
import Core
import DesignSystem

// MARK: - ImportLivePreviewPane

/// Third column of the iPad 3-column import layout.
///
/// Shows the first 10 rows of the uploaded file with column headers resolved
/// through the current `columnMapping`. Cells from unmapped columns show with
/// a muted tint; mapped columns are highlighted. Updates reactively as the
/// user adjusts mappings in the middle column.
public struct ImportLivePreviewPane: View {

    // MARK: - Input

    /// Preview data (columns + first rows).
    public let preview: ImportPreview

    /// Current source-column → CRM-field mapping.
    /// Key = source column name, Value = CRMField.rawValue.
    public let columnMapping: [String: String]

    // MARK: - Init

    public init(preview: ImportPreview, columnMapping: [String: String]) {
        self.preview = preview
        self.columnMapping = columnMapping
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if preview.rows.isEmpty {
                emptyState
            } else {
                tableContent
            }
        }
        .background(Color.bizarreSurfaceBase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live data preview")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Live Preview")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("First \(min(preview.rows.count, 10)) of \(preview.totalRows) rows")
                    .font(.system(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            mappingStatusBadge
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .brandGlass(.regular, in: Rectangle(), tint: nil)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Mapping status badge

    private var mappingStatusBadge: some View {
        let mappedCount = columnMapping.values.filter { !$0.isEmpty }.count
        let total = preview.columns.count
        let allMapped = mappedCount == total

        return BrandGlassBadge(
            "\(mappedCount)/\(total) mapped",
            variant: .regular,
            tint: allMapped ? .bizarreSuccess : .bizarreWarning
        )
        .accessibilityLabel("\(mappedCount) of \(total) columns mapped")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "tablecells")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No preview rows")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No preview data available")
    }

    // MARK: - Table content

    private var tableContent: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                columnHeaderRow
                Divider()
                ForEach(Array(preview.rows.prefix(10).enumerated()), id: \.offset) { rowIdx, row in
                    dataRow(row: row, index: rowIdx)
                    if rowIdx < min(preview.rows.count, 10) - 1 {
                        Divider()
                            .padding(.leading, DesignTokens.Spacing.md)
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
    }

    // MARK: - Column header row

    private var columnHeaderRow: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            ForEach(preview.columns, id: \.self) { col in
                columnHeader(col)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private func columnHeader(_ col: String) -> some View {
        let isMapped = columnMapping[col]?.isEmpty == false
        let crmFieldName = columnMapping[col].flatMap { CRMField(rawValue: $0)?.displayName }

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(col)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isMapped ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                .lineLimit(1)
                .frame(minWidth: 90, alignment: .leading)

            if let crm = crmFieldName {
                Text(crm)
                    .font(.system(size: 10))
                    .foregroundStyle(.bizarreSuccess)
                    .lineLimit(1)
            } else {
                Text("Unmapped")
                    .font(.system(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.7))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(col + (isMapped ? ", mapped to \(crmFieldName ?? "")" : ", unmapped"))
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Data row

    private func dataRow(row: [String], index: Int) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.lg) {
            ForEach(Array(preview.columns.enumerated()), id: \.offset) { colIdx, col in
                let cell = colIdx < row.count ? row[colIdx] : ""
                let isMapped = columnMapping[col]?.isEmpty == false
                let hasError = preview.flaggedRows.contains { $0.row == index + 1 && ($0.column == col || $0.column == nil) }

                Text(cell.isEmpty ? "—" : cell)
                    .font(.system(size: 12))
                    .foregroundStyle(cellForegroundColor(isMapped: isMapped, hasError: hasError))
                    .lineLimit(1)
                    .frame(minWidth: 90, alignment: .leading)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background {
                        if hasError {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(Color.bizarreError.opacity(0.12))
                        }
                    }
                    .accessibilityLabel(cell.isEmpty ? "Empty" : cell)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(index % 2 == 0 ? Color.clear : Color.bizarreSurface1.opacity(0.3))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Row \(index + 1): \(row.joined(separator: ", "))")
    }

    // MARK: - Helpers

    private func cellForegroundColor(isMapped: Bool, hasError: Bool) -> Color {
        if hasError   { return .bizarreError }
        if isMapped   { return .bizarreOnSurface }
        return .bizarreOnSurfaceMuted
    }
}
