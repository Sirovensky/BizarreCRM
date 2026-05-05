import SwiftUI
import Core
import DesignSystem

// MARK: - ImportPreviewView

public struct ImportPreviewView: View {
    @Bindable var vm: ImportWizardViewModel

    public init(vm: ImportWizardViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if vm.isLoading {
                loadingState
            } else if let p = vm.preview {
                previewContent(p)
            } else if let err = vm.errorMessage {
                errorState(err)
            } else {
                loadingState
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .task { await vm.loadPreview() }
    }

    private var loadingState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
            Text("Loading preview…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Preview failed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.loadPreview() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func previewContent(_ p: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            // Header summary
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Detected \(p.columns.count) column\(p.columns.count == 1 ? "" : "s"), \(p.totalRows) row\(p.totalRows == 1 ? "" : "s")")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if p.totalRows > 50_000 {
                    Label("Large file — \(p.totalRows) rows may take several minutes", systemImage: "exclamationmark.triangle")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityLabel("Warning: large file with \(p.totalRows) rows")
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .accessibilityAddTraits(.isHeader)

            Divider()

            if Platform.isCompact {
                iPhoneTable(p)
            } else {
                iPadTable(p)
            }
        }
        .padding(.top, DesignTokens.Spacing.lg)
    }

    // iPad: SwiftUI Table
    @ViewBuilder
    private func iPadTable(_ p: ImportPreview) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: DesignTokens.Spacing.lg, verticalSpacing: DesignTokens.Spacing.sm) {
                // Header row
                GridRow {
                    ForEach(p.columns, id: \.self) { col in
                        Text(col)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOrange)
                            .bold()
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                Divider()
                // Data rows
                ForEach(Array(p.rows.prefix(10).enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            Text(cell.isEmpty ? "—" : cell)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }

    // iPhone: horizontal scrollable grid
    private func iPhoneTable(_ p: ImportPreview) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: DesignTokens.Spacing.lg) {
                    ForEach(p.columns, id: \.self) { col in
                        Text(col)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOrange)
                            .bold()
                            .frame(minWidth: 100, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .padding(DesignTokens.Spacing.md)

                Divider()

                // Rows
                ForEach(Array(p.rows.prefix(10).enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: DesignTokens.Spacing.lg) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            Text(cell.isEmpty ? "—" : cell)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .lineLimit(1)
                                .frame(minWidth: 100, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(rowIdx % 2 == 0 ? Color.clear : Color.bizarreSurface1.opacity(0.5))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Row \(rowIdx + 1): \(row.joined(separator: ", "))")
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }
}
