import SwiftUI
import Core
import DesignSystem

// MARK: - ImportStartView

public struct ImportStartView: View {
    @Bindable var vm: ImportWizardViewModel

    public init(vm: ImportWizardViewModel) {
        self.vm = vm
    }

    private var rowCount: Int { vm.preview?.totalRows ?? 0 }
    private var sourceName: String { vm.selectedSource?.displayName ?? "file" }
    private var entityName: String { vm.selectedEntity.displayName }
    private var filename: String { vm.selectedFilename ?? "your file" }

    public var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xxl) {
                header

                summaryCard

                mappingSummary

                if let err = vm.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .accessibilityLabel("Error: \(err)")
                }

                startButton
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }
            .padding(.top, DesignTokens.Spacing.xxl)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Confirm Import")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("Review details before starting")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityAddTraits(.isHeader)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Import summary")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            row(label: "Source", value: sourceName)
            Divider()
            row(label: "Entity", value: entityName)
            Divider()
            row(label: "File", value: filename)
            Divider()
            row(label: "\(entityName) to import", value: "\(rowCount)")
        }
        .padding(DesignTokens.Spacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    private var mappingSummary: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("\(vm.columnMapping.count) column\(vm.columnMapping.count == 1 ? "" : "s") mapped")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityLabel("\(vm.columnMapping.count) columns will be imported")
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var startButton: some View {
        Button("Start Import") {
            Task { await vm.startImport() }
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .disabled(vm.isLoading)
        .accessibilityIdentifier("import.start.button")
        .overlay {
            if vm.isLoading {
                ProgressView().padding(.trailing, DesignTokens.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
