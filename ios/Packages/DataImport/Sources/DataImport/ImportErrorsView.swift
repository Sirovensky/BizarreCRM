import SwiftUI
import Core
import DesignSystem

// MARK: - ImportErrorsView

public struct ImportErrorsView: View {
    @Bindable var vm: ImportWizardViewModel

    public init(vm: ImportWizardViewModel) {
        self.vm = vm
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.rowErrors.isEmpty {
                emptyState
            } else {
                errorList
            }

            bottomBar
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Import Errors")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("\(vm.rowErrors.count) row\(vm.rowErrors.count == 1 ? "" : "s") had issues")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.lg)
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No errors found")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorList: some View {
        List(vm.rowErrors) { err in
            ErrorRow(error: err)
                .listRowBackground(Color.bizarreSurface1)
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    private var bottomBar: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // Export errors button — stub (out of scope per spec)
            Button("Export Errors (TODO)") { /* out of scope */ }
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .disabled(true)
                .accessibilityLabel("Export errors — not yet available")
                .accessibilityIdentifier("import.errors.export")

            Button("Back") { vm.backFromErrors() }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("import.errors.back")
        }
        .padding(DesignTokens.Spacing.lg)
    }
}

// MARK: - Error row

private struct ErrorRow: View {
    let error: ImportRowError

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .font(.system(size: 16))
                .accessibilityHidden(true)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Row \(error.row)")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let col = error.column {
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text(col)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOrange)
                    }
                }
                Text(error.reason)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["Row \(error.row)"]
        if let col = error.column { parts.append("Column \(col)") }
        parts.append(error.reason)
        return parts.joined(separator: ". ")
    }
}
