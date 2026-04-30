#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - DimensionsInputView

/// §6.3 — Three-field (W × H × D) dimensions input with live formatted preview.
///
/// Formats entered values as `"W × H × D cm"` in real time. Each field accepts
/// decimal input and strips non-numeric characters on change. The unit label is
/// configurable (defaults to "cm"). All three fields are optional — the formatter
/// only shows the dimensions that have values.
///
/// Usage:
/// ```swift
/// DimensionsInputView(width: $width, height: $height, depth: $depth)
/// ```
public struct DimensionsInputView: View {

    // MARK: Bindings

    @Binding public var width: String
    @Binding public var height: String
    @Binding public var depth: String

    // MARK: Config

    public var unit: String = "cm"

    // MARK: Focus

    @FocusState private var focus: Axis?
    private enum Axis: Hashable { case width, height, depth }

    // MARK: Init

    public init(
        width: Binding<String>,
        height: Binding<String>,
        depth: Binding<String>,
        unit: String = "cm"
    ) {
        self._width = width
        self._height = height
        self._depth = depth
        self.unit = unit
    }

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            fieldsRow
            if !formattedPreview.isEmpty {
                Text(formattedPreview)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .transition(.opacity)
                    .accessibilityLabel("Dimensions: \(formattedPreview)")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: formattedPreview)
    }

    // MARK: - Fields row

    private var fieldsRow: some View {
        HStack(spacing: BrandSpacing.xs) {
            dimensionField("W", text: $width, axis: .width)
            separator
            dimensionField("H", text: $height, axis: .height)
            separator
            dimensionField("D", text: $depth, axis: .depth)
            Text(unit)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var separator: some View {
        Text("×")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dimensionField(
        _ placeholder: String,
        text: Binding<String>,
        axis: Axis
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .focused($focus, equals: axis)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .frame(minWidth: 52)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bizarreSurface1)
            )
            .onChange(of: text.wrappedValue) { _, new in
                text.wrappedValue = Self.sanitize(new)
            }
            .accessibilityLabel(
                placeholder == "W" ? "Width in \(unit)"
                    : placeholder == "H" ? "Height in \(unit)"
                    : "Depth in \(unit)"
            )
    }

    // MARK: - Formatted preview

    /// Returns a formatted string like "12.5 × 8 × 3 cm" from whichever
    /// fields have non-empty values. Returns empty string when all three are empty.
    var formattedPreview: String {
        let parts: [(label: String, raw: String)] = [
            ("W", width), ("H", height), ("D", depth)
        ]
        let nonEmpty = parts.filter { !$0.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return "" }
        let formatted = nonEmpty.map { Self.format($0.raw) }.joined(separator: " × ")
        return "\(formatted) \(unit)"
    }

    // MARK: - Helpers

    /// Strips characters that are not digits or the locale decimal separator.
    static func sanitize(_ raw: String) -> String {
        let sep = Locale.current.decimalSeparator ?? "."
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: sep))
        return String(raw.unicodeScalars.filter { allowed.contains($0) })
    }

    /// Formats a raw decimal string by stripping trailing zeros after the separator.
    static func format(_ raw: String) -> String {
        guard let value = Double(raw.replacingOccurrences(of: ",", with: ".")) else {
            return raw
        }
        var result = String(format: "%.2f", value)
        while result.hasSuffix("0") { result = String(result.dropLast()) }
        if result.hasSuffix(".") { result = String(result.dropLast()) }
        return result.isEmpty ? "0" : result
    }
}
#endif
