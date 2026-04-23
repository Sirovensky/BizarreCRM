import SwiftUI
import Core
import DesignSystem

// MARK: - ImportColumnMappingView

public struct ImportColumnMappingView: View {
    @Bindable var vm: ImportWizardViewModel

    public init(vm: ImportWizardViewModel) {
        self.vm = vm
    }

    private var sourceColumns: [String] {
        vm.preview?.columns ?? []
    }

    /// CRM fields available for the currently-selected entity type.
    private var entityFields: [CRMField] {
        CRMField.fields(for: vm.selectedEntity)
    }

    public var body: some View {
        if Platform.isCompact {
            compactLayout
        } else {
            wideLayout
        }
    }

    // MARK: - iPhone layout

    private var compactLayout: some View {
        VStack(spacing: 0) {
            header

            if vm.allRequiredMapped {
                requiredMappedBadge
            } else {
                missingFieldsBadge
            }

            List {
                Section("Column Mapping — \(vm.selectedEntity.displayName)") {
                    ForEach(sourceColumns, id: \.self) { col in
                        columnRow(for: col)
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)

            continueButton
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.lg)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - iPad layout (wider grid)

    private var wideLayout: some View {
        VStack(spacing: 0) {
            header

            if vm.allRequiredMapped {
                requiredMappedBadge
            } else {
                missingFieldsBadge
            }

            // iPad: show mapping as a Grid for denser visual
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Column header row
                    Grid(alignment: .leading, horizontalSpacing: DesignTokens.Spacing.lg) {
                        GridRow {
                            Text("Source Column")
                                .font(.brandBodyLarge().bold())
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityAddTraits(.isHeader)
                            Text("Maps To (\(vm.selectedEntity.displayName))")
                                .font(.brandBodyLarge().bold())
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Divider()
                        ForEach(sourceColumns, id: \.self) { col in
                            GridRow {
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                    Text(col)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurface)
                                    if let mapped = vm.columnMapping[col],
                                       let field = CRMField(rawValue: mapped), field.isRequired {
                                        Label("Required", systemImage: "star.fill")
                                            .font(.brandLabelSmall())
                                            .foregroundStyle(.bizarreOrange)
                                    }
                                }
                                Picker("Map \(col)", selection: bindingForColumn(col)) {
                                    Text("(Skip)").tag(Optional<String>.none)
                                    ForEach(entityFields, id: \.rawValue) { field in
                                        Text(field.displayName).tag(Optional(field.rawValue))
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .accessibilityLabel("Map column \(col)")
                                .accessibilityIdentifier("import.mapping.\(col)")
                            }
                            .padding(.vertical, DesignTokens.Spacing.xs)
                        }
                    }
                    .padding(DesignTokens.Spacing.lg)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                }
            }

            continueButton
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.lg)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Map Columns")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("Match your file's columns to \(vm.selectedEntity.displayName) fields")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.lg)
        .accessibilityAddTraits(.isHeader)
    }

    private var requiredMappedBadge: some View {
        Label("All required fields mapped", systemImage: "checkmark.circle.fill")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreSuccess)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.sm)
            .accessibilityLabel("All required fields are mapped. You can continue.")
    }

    private var missingFieldsBadge: some View {
        let missing = vm.missingRequiredFields.map { $0.displayName }.joined(separator: ", ")
        return Label("Still required: \(missing)", systemImage: "exclamationmark.circle")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreWarning)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.sm)
            .accessibilityLabel("Still required: \(missing)")
    }

    private func columnRow(for col: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(col)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let mapped = vm.columnMapping[col],
                   let field = CRMField(rawValue: mapped),
                   field.isRequired {
                    Label("Required", systemImage: "star.fill")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                }
            }

            Spacer()

            Picker("Map \(col)", selection: bindingForColumn(col)) {
                Text("(Skip)").tag(Optional<String>.none)
                ForEach(entityFields, id: \.rawValue) { field in
                    Text(field.displayName).tag(Optional(field.rawValue))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("Map column \(col)")
            .accessibilityIdentifier("import.mapping.\(col)")
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func bindingForColumn(_ col: String) -> Binding<String?> {
        Binding(
            get: { vm.columnMapping[col] },
            set: { newVal in
                var updated = vm.columnMapping
                if let v = newVal {
                    updated[col] = v
                } else {
                    updated.removeValue(forKey: col)
                }
                vm.columnMapping = updated
            }
        )
    }

    private var continueButton: some View {
        Button("Continue to Confirm") { vm.confirmMapping() }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(!vm.allRequiredMapped)
            .accessibilityIdentifier("import.mapping.continue")
            .accessibilityLabel(vm.allRequiredMapped
                ? "Continue to confirmation"
                : "Continue, disabled — map all required fields first")
    }
}
