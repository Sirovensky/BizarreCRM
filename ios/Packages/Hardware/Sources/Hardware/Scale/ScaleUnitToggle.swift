#if canImport(SwiftUI)
import SwiftUI

// MARK: - ScaleUnitToggle
//
// §17.6 — Scale unit toggle (oz / g quick-switch).
//
// Provides:
//   1. `ScaleUnitToggle`            — compact segmented toggle for oz ↔ g (or all 4 units).
//   2. `WeightDisplayChipWithToggle`— `WeightDisplayChip` + inline oz/g toggle wired to
//      `WeightUnitStore`; replaces bare `WeightDisplayChip` in POS contexts where the
//      unit must be changeable mid-session.
//
// Design intent:
//   - The compact (2-unit) variant shows only Grams and Ounces — the most common
//     deli / postal use-case. The full variant exposes all four `WeightUnit` cases.
//   - Selection is immediately persisted via `WeightUnitStore` so the POS cart
//     formatter and the display chip stay in sync.
//   - Accessibility: each segment has an explicit label and the selected segment
//     announces its new value on change.

// MARK: - ScaleUnitToggle

/// Compact segmented toggle for switching between weight display units.
///
/// The `compact` style shows Grams and Ounces only (the most common quick-switch).
/// The `full` style shows all four `WeightUnit` options.
///
/// ```swift
/// ScaleUnitToggle(selected: $selectedUnit)             // compact (g/oz)
/// ScaleUnitToggle(selected: $selectedUnit, style: .full) // all 4
/// ```
public struct ScaleUnitToggle: View {

    public enum Style {
        /// Shows only Grams (g) and Ounces (oz).
        case compact
        /// Shows all four `WeightUnit` cases.
        case full
    }

    @Binding public var selected: WeightUnit
    public let style: Style

    public init(selected: Binding<WeightUnit>, style: Style = .compact) {
        self._selected = selected
        self.style = style
    }

    // MARK: - Body

    public var body: some View {
        Picker("Weight Unit", selection: $selected) {
            ForEach(displayedUnits, id: \.self) { unit in
                Text(unit.shortLabel)
                    .tag(unit)
                    .accessibilityLabel(unit.displayName)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityLabel("Weight unit: \(selected.displayName)")
        .onChange(of: selected) { _, newUnit in
            UIAccessibility.post(
                notification: .announcement,
                argument: "Weight unit changed to \(newUnit.displayName)"
            )
        }
    }

    // MARK: - Private

    private var displayedUnits: [WeightUnit] {
        switch style {
        case .compact: return [.grams, .ounces]
        case .full:    return WeightUnit.allCases
        }
    }
}

// MARK: - WeightDisplayChipWithToggle
//
// Combines `WeightDisplayChip` with an inline `ScaleUnitToggle`.
// Reads/writes the unit via `WeightUnitStore` so changes are persisted and
// survive navigation away.

/// `WeightDisplayChip` with an attached oz/g unit toggle.
///
/// Replaces bare `WeightDisplayChip` in POS contexts where the operator needs to
/// switch units mid-session without opening Settings.
///
/// ```swift
/// WeightDisplayChipWithToggle(
///     weight: viewModel.currentWeight,
///     unitStore: viewModel.unitStore,
///     onTare: { await viewModel.tare() }
/// )
/// ```
public struct WeightDisplayChipWithToggle: View {

    public let weight: Weight?
    public let onTare: (() async -> Void)?

    @State private var unitStore: WeightUnitStore
    @State private var selectedUnit: WeightUnit

    public init(
        weight: Weight?,
        unitStore: WeightUnitStore = WeightUnitStore(),
        onTare: (() async -> Void)? = nil
    ) {
        self.weight = weight
        self.onTare = onTare
        let store = unitStore
        self._unitStore = State(initialValue: store)
        self._selectedUnit = State(initialValue: store.selectedUnit)
    }

    public var body: some View {
        HStack(spacing: 8) {
            formattedChip
            ScaleUnitToggle(selected: $selectedUnit, style: .compact)
                .onChange(of: selectedUnit) { _, newUnit in
                    unitStore.selectedUnit = newUnit
                }
        }
    }

    // MARK: - Chip

    @ViewBuilder
    private var formattedChip: some View {
        HStack(spacing: 6) {
            stabilityDot
            weightLabel
            if let tare = onTare {
                Divider().frame(height: 14).opacity(0.4)
                tareButton(action: tare)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var stabilityDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var weightLabel: some View {
        Group {
            if let w = weight {
                Text(selectedUnit.formatted(w))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            } else {
                Text("\u{2014}")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func tareButton(action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text("Tare")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tare scale — zero the current weight")
        .accessibilityIdentifier("scale.tare")
    }

    private var dotColor: Color {
        guard let w = weight else { return .gray }
        return w.isStable ? .green : .orange
    }

    private var accessibilityText: String {
        guard let w = weight else { return "No weight reading" }
        let stability = w.isStable ? "stable" : "settling"
        return "\(selectedUnit.formatted(w)), \(stability)"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ScaleUnitToggle") {
    @Previewable @State var unit: WeightUnit = .grams
    VStack(spacing: 24) {
        ScaleUnitToggle(selected: $unit)
        ScaleUnitToggle(selected: $unit, style: .full)
        Text("Selected: \(unit.displayName)")
            .foregroundStyle(.secondary)
    }
    .padding()
}

#Preview("WeightDisplayChipWithToggle") {
    VStack(spacing: 20) {
        WeightDisplayChipWithToggle(weight: Weight(grams: 350, isStable: true))
        WeightDisplayChipWithToggle(weight: Weight(grams: 1250, isStable: false))
        WeightDisplayChipWithToggle(weight: nil)
        WeightDisplayChipWithToggle(
            weight: Weight(grams: 500, isStable: true),
            onTare: { try? await Task.sleep(nanoseconds: 500_000_000) }
        )
    }
    .padding()
}
#endif
#endif
