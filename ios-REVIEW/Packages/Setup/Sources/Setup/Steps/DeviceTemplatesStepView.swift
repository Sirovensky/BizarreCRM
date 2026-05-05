import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
final class DeviceTemplatesViewModel {

    // MARK: State

    var selectedFamilies: Set<DeviceFamily> = []
    var selectedPricingMode: SetupRepairPricingMode = .tiered
    var tierDefaults: RepairPricingSeedPricing = SetupRepairPricingSelection.defaultTierDefaults
    var autoMarginPreset: RepairPricingAutoMarginPreset = .midTraffic
    var autoMarginTargetType: RepairPricingAutoMarginTargetType = .percent
    var targetMarginPct: Double = 100
    var targetProfitAmount: Double = 80
    var calculationBasis: RepairPricingAutoMarginBasis = .markup
    var roundingMode: RepairPricingRoundingMode = .ending99
    var capPct: Double = 25
    var autoMarginRules: [RepairPricingAutoMarginRule] = SetupRepairPricingSelection.defaultAutoMarginRules(for: .midTraffic, targetType: .percent)
    var spreadsheetRows: [SetupSpreadsheetPriceDraft] = []
    var spreadsheetIsLoading = false
    var spreadsheetLoadError: String?

    // MARK: Helpers

    var isNextEnabled: Bool {
        Step11Validator.isNextEnabled(selected: selectedFamilies)
    }

    func toggleFamily(_ family: DeviceFamily) {
        if selectedFamilies.contains(family) {
            selectedFamilies.remove(family)
        } else {
            selectedFamilies.insert(family)
        }
    }

    func selectAll() {
        selectedFamilies = Set(DeviceFamily.allCases)
    }

    func selectNone() {
        selectedFamilies = []
    }

    var setupSelection: DeviceTemplatesSetupSelection {
        DeviceTemplatesSetupSelection(
            families: selectedFamilies,
            repairPricing: SetupRepairPricingSelection(
                mode: selectedPricingMode,
                tierDefaults: tierDefaults,
                spreadsheetPrices: spreadsheetRows,
                autoMarginPreset: autoMarginPreset,
                autoMarginTargetType: autoMarginTargetType,
                targetMarginPct: targetMarginPct,
                targetProfitAmount: targetProfitAmount,
                calculationBasis: calculationBasis,
                roundingMode: roundingMode,
                capPct: capPct,
                autoMarginRules: autoMarginRules
            )
        )
    }

    func setTierDefault(service: String, tier: String, value: Double) {
        var serviceDefaults = tierDefaults[service] ?? [:]
        serviceDefaults[tier] = max(0, value)
        tierDefaults[service] = serviceDefaults
    }

    func loadSpreadsheetMatrix(repository: any SetupRepository) async {
        guard !spreadsheetIsLoading, spreadsheetRows.isEmpty else { return }
        spreadsheetIsLoading = true
        spreadsheetLoadError = nil
        defer { spreadsheetIsLoading = false }

        do {
            let matrix = try await repository.fetchRepairPricingMatrixPreview(category: "phone", limit: 25)
            spreadsheetRows = matrix.devices.flatMap { device in
                device.prices.map { price in
                    SetupSpreadsheetPriceDraft(
                        deviceModelId: device.deviceModelId,
                        deviceModelName: device.deviceModelName,
                        manufacturerName: device.manufacturerName,
                        repairServiceId: price.repairServiceId,
                        repairServiceName: price.repairServiceName,
                        repairServiceSlug: price.repairServiceSlug,
                        priceId: price.priceId,
                        laborPrice: price.laborPrice
                    )
                }
            }
        } catch {
            spreadsheetLoadError = error.localizedDescription
        }
    }

    var spreadsheetDeviceIds: [Int64] {
        var seen = Set<Int64>()
        var ids: [Int64] = []
        for row in spreadsheetRows where !seen.contains(row.deviceModelId) {
            seen.insert(row.deviceModelId)
            ids.append(row.deviceModelId)
        }
        return ids
    }

    func rows(for deviceModelId: Int64) -> [SetupSpreadsheetPriceDraft] {
        spreadsheetRows.filter { $0.deviceModelId == deviceModelId }
    }

    func setSpreadsheetPrice(rowId: String, value: Double) {
        guard let index = spreadsheetRows.firstIndex(where: { $0.id == rowId }) else { return }
        spreadsheetRows[index].laborPrice = max(0, value)
        spreadsheetRows[index].isEdited = true
    }

    func setAutoMarginPreset(_ preset: RepairPricingAutoMarginPreset) {
        autoMarginPreset = preset
        autoMarginRules = SetupRepairPricingSelection.defaultAutoMarginRules(for: preset, targetType: autoMarginTargetType)
    }

    func setAutoMarginTargetType(_ targetType: RepairPricingAutoMarginTargetType) {
        autoMarginTargetType = targetType
        autoMarginRules = SetupRepairPricingSelection.defaultAutoMarginRules(for: autoMarginPreset, targetType: targetType)
    }

    func setAutoMarginRule(_ ruleId: String, value: Double) {
        guard let index = autoMarginRules.firstIndex(where: { $0.id == ruleId }) else { return }
        if autoMarginTargetType == .fixedAmount {
            autoMarginRules[index].targetProfitAmount = max(0, value)
        } else {
            autoMarginRules[index].targetMarginPct = max(0, value)
        }
        autoMarginPreset = .custom
    }
}

// MARK: - View  (§36.2 Step 11 — Device Templates)

@MainActor
public struct DeviceTemplatesStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onSelectionChanged: (DeviceTemplatesSetupSelection) -> Void
    let repository: (any SetupRepository)?

    @State private var vm = DeviceTemplatesViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onSelectionChanged: @escaping (DeviceTemplatesSetupSelection) -> Void,
        repository: (any SetupRepository)? = nil
    ) {
        self.onValidityChanged = onValidityChanged
        self.onSelectionChanged = onSelectionChanged
        self.repository = repository
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: BrandSpacing.md)
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                header
                helperButtons
                familyGrid
                pricingSection
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            onValidityChanged(vm.isNextEnabled)
            publishSelection()
        }
        .onChange(of: vm.isNextEnabled) { _, valid in onValidityChanged(valid) }
        .onChange(of: vm.selectedFamilies) { _, _ in publishSelection() }
        .onChange(of: vm.selectedPricingMode) { _, mode in
            publishSelection()
            if mode == .spreadsheet {
                Task { await loadSpreadsheetMatrix() }
            }
        }
        .onChange(of: vm.tierDefaults) { _, _ in publishSelection() }
        .onChange(of: vm.spreadsheetRows) { _, _ in publishSelection() }
        .onChange(of: vm.autoMarginPreset) { _, _ in publishSelection() }
        .onChange(of: vm.autoMarginTargetType) { _, _ in publishSelection() }
        .onChange(of: vm.targetMarginPct) { _, _ in publishSelection() }
        .onChange(of: vm.targetProfitAmount) { _, _ in publishSelection() }
        .onChange(of: vm.calculationBasis) { _, _ in publishSelection() }
        .onChange(of: vm.roundingMode) { _, _ in publishSelection() }
        .onChange(of: vm.capPct) { _, _ in publishSelection() }
        .onChange(of: vm.autoMarginRules) { _, _ in publishSelection() }
    }

    // MARK: Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Device Templates")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.top, BrandSpacing.lg)
                .accessibilityAddTraits(.isHeader)

            Text("Select the device families you repair. This pre-loads models and service options for your ticket create screen.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    private var helperButtons: some View {
        HStack(spacing: BrandSpacing.sm) {
            Button("Add all") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.selectAll()
                }
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Select all device families")

            Button("Select none") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.selectNone()
                }
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Deselect all device families")

            Spacer()

            if !vm.selectedFamilies.isEmpty {
                Text("\(vm.selectedFamilies.count) selected")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityLabel("\(vm.selectedFamilies.count) families selected")
            }
        }
    }

    private var familyGrid: some View {
        LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
            ForEach(DeviceFamily.allCases, id: \.self) { family in
                familyCard(family)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Device family selection grid")
    }

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Repair Pricing")
                    .font(.brandTitleSmall())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("Choose how phone repair prices should be initialized on the server.")
                    .font(.brandBodySmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }

            Picker("Pricing mode", selection: $vm.selectedPricingMode) {
                ForEach(SetupRepairPricingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Repair pricing mode")

            switch vm.selectedPricingMode {
            case .tiered:
                tierDefaultsEditor
            case .spreadsheet:
                spreadsheetEditor
            case .autoMargin:
                autoMarginControls
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.bizarreOutline.opacity(0.25), lineWidth: 1)
        )
    }

    private var tierDefaultsEditor: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(SetupRepairPricingSelection.defaultServiceOrder, id: \.self) { service in
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text(SetupRepairPricingSelection.serviceTitle(service))
                        .font(.brandLabelLarge())
                        .foregroundStyle(Color.bizarreOnSurface)

                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(SetupRepairPricingSelection.defaultTierOrder, id: \.self) { tier in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SetupRepairPricingSelection.tierTitle(tier))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                                TextField(
                                    SetupRepairPricingSelection.tierTitle(tier),
                                    value: tierPriceBinding(service: service, tier: tier),
                                    format: .number.precision(.fractionLength(0...2))
                                )
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("\(SetupRepairPricingSelection.serviceTitle(service)) tier \(SetupRepairPricingSelection.tierTitle(tier)) labor price")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var spreadsheetEditor: some View {
        if vm.spreadsheetIsLoading {
            HStack(spacing: BrandSpacing.sm) {
                ProgressView()
                Text("Loading price matrix")
                    .font(.brandBodySmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = vm.spreadsheetLoadError {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text(error)
                    .font(.brandBodySmall())
                    .foregroundStyle(Color.bizarreError)
                Button("Retry") {
                    Task { await loadSpreadsheetMatrix(force: true) }
                }
                .buttonStyle(.brandGlass)
            }
        } else if vm.spreadsheetRows.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Labor-only starter matrix")
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                Text("This edits labor prices only. Parts, taxes, fees, and the final customer total stay separate.")
                    .font(.brandBodySmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                Button {
                    Task { await loadSpreadsheetMatrix(force: true) }
                } label: {
                    Label("Load first 25 devices", systemImage: "tablecells")
                        .font(.brandLabelLarge())
                }
                .buttonStyle(.brandGlass)
            }
        } else {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                Text("Labor only")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOrange)
                ForEach(vm.spreadsheetDeviceIds, id: \.self) { deviceId in
                    spreadsheetDeviceEditor(deviceId)
                }
            }
        }
    }

    private func spreadsheetDeviceEditor(_ deviceId: Int64) -> some View {
        let rows = vm.rows(for: deviceId)
        let title = rows.first.map { "\($0.manufacturerName) \($0.deviceModelName)" } ?? "Device"

        return VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurface)

            ForEach(rows) { row in
                HStack(spacing: BrandSpacing.sm) {
                    Text(row.repairServiceName)
                        .font(.brandBodySmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .lineLimit(1)

                    Spacer()

                    TextField(
                        row.repairServiceName,
                        value: spreadsheetPriceBinding(rowId: row.id),
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .accessibilityLabel("\(title) \(row.repairServiceName) labor price")
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private var autoMarginControls: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Traffic preset")
                    .font(.brandLabelLarge())
                Picker("Traffic preset", selection: autoMarginPresetBinding) {
                    ForEach([RepairPricingAutoMarginPreset.highTraffic, .midTraffic, .lowTraffic, .custom], id: \.self) { preset in
                        Text(preset.setupTitle).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Target style")
                    .font(.brandLabelLarge())
                Picker("Target style", selection: autoMarginTargetTypeBinding) {
                    ForEach(RepairPricingAutoMarginTargetType.allCases, id: \.self) { type in
                        Text(type.setupTitle).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text(vm.autoMarginTargetType == .fixedAmount ? "Profit dollars by repair type" : "Markup percent by repair type")
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurface)

                ForEach(vm.autoMarginRules) { rule in
                    HStack(spacing: BrandSpacing.sm) {
                        Text(rule.label ?? SetupRepairPricingSelection.serviceTitle(rule.repairServiceSlug ?? ""))
                            .font(.brandBodySmall())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            .lineLimit(1)

                        Spacer()

                        TextField(
                            rule.label ?? "Target",
                            value: autoMarginRuleBinding(ruleId: rule.id ?? ""),
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)

                        Text(vm.autoMarginTargetType.setupTitle)
                            .font(.brandLabelSmall())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            .frame(width: 24, alignment: .leading)
                    }
                }
            }

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Round up")
                    .font(.brandLabelLarge())
                Picker("Round up", selection: $vm.roundingMode) {
                    ForEach(RepairPricingRoundingMode.allCases, id: \.self) { mode in
                        Text(mode.setupTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                HStack {
                    Text("Safety cap")
                        .font(.brandLabelLarge())
                    Spacer()
                    Text("\(Int(vm.capPct))%")
                        .font(.brandLabelLarge())
                        .foregroundStyle(Color.bizarreOrange)
                }
                Slider(value: $vm.capPct, in: 0...100, step: 1)
                    .accessibilityLabel("Auto margin safety cap percent")
            }
        }
    }

    private func familyCard(_ family: DeviceFamily) -> some View {
        let isSelected = vm.selectedFamilies.contains(family)
        return Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.2)) {
                vm.toggleFamily(family)
            }
        } label: {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: family.systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)

                Text(family.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(isSelected ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)

                if family.preloadedModelCount > 0 {
                    Text("\(family.preloadedModelCount) models")
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.bizarreOrange)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(BrandSpacing.md)
            .background(
                isSelected ? Color.bizarreOrange.opacity(0.1) : Color.bizarreSurface1.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.bizarreOrange.opacity(0.6) : Color.bizarreOutline.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to \(isSelected ? "deselect" : "select") \(family.displayName)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func tierPriceBinding(service: String, tier: String) -> Binding<Double> {
        Binding(
            get: {
                vm.tierDefaults[service]?[tier] ?? 0
            },
            set: { value in
                vm.setTierDefault(service: service, tier: tier, value: value)
            }
        )
    }

    private func spreadsheetPriceBinding(rowId: String) -> Binding<Double> {
        Binding(
            get: {
                vm.spreadsheetRows.first(where: { $0.id == rowId })?.laborPrice ?? 0
            },
            set: { value in
                vm.setSpreadsheetPrice(rowId: rowId, value: value)
            }
        )
    }

    private var autoMarginPresetBinding: Binding<RepairPricingAutoMarginPreset> {
        Binding(
            get: { vm.autoMarginPreset },
            set: { preset in vm.setAutoMarginPreset(preset) }
        )
    }

    private var autoMarginTargetTypeBinding: Binding<RepairPricingAutoMarginTargetType> {
        Binding(
            get: { vm.autoMarginTargetType },
            set: { type in vm.setAutoMarginTargetType(type) }
        )
    }

    private func autoMarginRuleBinding(ruleId: String) -> Binding<Double> {
        Binding(
            get: {
                guard let rule = vm.autoMarginRules.first(where: { $0.id == ruleId }) else { return 0 }
                return vm.autoMarginTargetType == .fixedAmount
                    ? rule.targetProfitAmount ?? 0
                    : rule.targetMarginPct
            },
            set: { value in
                vm.setAutoMarginRule(ruleId, value: value)
            }
        )
    }

    private func publishSelection() {
        onSelectionChanged(vm.setupSelection)
    }

    private func loadSpreadsheetMatrix(force: Bool = false) async {
        guard let repository else { return }
        if force {
            vm.spreadsheetRows = []
        }
        await vm.loadSpreadsheetMatrix(repository: repository)
        publishSelection()
    }
}
