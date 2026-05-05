import SwiftUI
import Core
import DesignSystem

// MARK: - §43.5 New Service Inline Form

/// Editable row for a single inline service inside the device template editor.
/// Caller owns the `InlineService` binding — this view is purely presentational.
@MainActor
struct NewServiceInlineForm: View {
    let index: Int
    let service: InlineService
    let onNameChange: (String) -> Void
    let onPriceChange: (String) -> Void
    let onDescriptionChange: (String) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text("Service \(index + 1)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Remove service \(index + 1)")
                .accessibilityIdentifier("templateEditor.removeService.\(index)")
            }

            // Name
            TextField("Service name (required)", text: Binding(
                get: { service.name },
                set: { onNameChange($0) }
            ))
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .accessibilityLabel("Service \(index + 1) name")
            .accessibilityIdentifier("templateEditor.serviceName.\(index)")

            // Price
            HStack {
                Text("$")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("0.00", text: Binding(
                    get: { service.rawPrice },
                    set: { onPriceChange($0) }
                ))
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Service \(index + 1) price in dollars")
                .accessibilityIdentifier("templateEditor.servicePrice.\(index)")
            }

            // Description
            TextField("Description (optional)", text: Binding(
                get: { service.description },
                set: { onDescriptionChange($0) }
            ))
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .accessibilityLabel("Service \(index + 1) description")
            .accessibilityIdentifier("templateEditor.serviceDesc.\(index)")
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
    }
}
