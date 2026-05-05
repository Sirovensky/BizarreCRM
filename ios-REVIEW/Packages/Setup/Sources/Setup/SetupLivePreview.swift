import SwiftUI
import Core
import DesignSystem

// MARK: - SetupLivePreview  (§36 iPad three-pane — right column)
//
// Shows a live read-back of the data the user has entered so far in the wizard.
// Updates reactively as `wizardPayload` changes.
// Displayed only in the three-pane iPad layout (width ≥ 900pt).

struct SetupLivePreview: View {

    let payload: SetupPayload
    let currentStep: SetupStep

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                previewHeader

                if !payload.companyName.isEmpty {
                    previewSection(title: "Business") {
                        previewRow(icon: "building.2", label: "Name",    value: payload.companyName)
                        if !payload.companyAddress.isEmpty {
                            previewRow(icon: "map",         label: "Address", value: payload.companyAddress)
                        }
                        if !payload.companyPhone.isEmpty {
                            previewRow(icon: "phone",        label: "Phone",   value: payload.companyPhone)
                        }
                    }
                }

                if let tz = payload.timezone {
                    previewSection(title: "Locale") {
                        previewRow(icon: "clock",     label: "Timezone", value: tz)
                        if let cu = payload.currency { previewRow(icon: "dollarsign.circle", label: "Currency", value: cu) }
                        if let lo = payload.locale   { previewRow(icon: "globe",             label: "Locale",   value: lo) }
                    }
                }

                if let tax = payload.taxRate {
                    previewSection(title: "Tax") {
                        previewRow(icon: "percent",  label: tax.name, value: "\(String(format: "%.2f", tax.ratePct))%")
                        previewRow(icon: "tag",      label: "Applies to", value: tax.applyTo.displayName)
                    }
                }

                if !payload.paymentMethods.isEmpty {
                    previewSection(title: "Payments") {
                        ForEach(payload.paymentMethods.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { method in
                            previewRow(icon: method.systemImage, label: method.displayName, value: nil)
                        }
                    }
                }

                if let loc = payload.firstLocation {
                    previewSection(title: "Location") {
                        previewRow(icon: "storefront", label: "Name",    value: loc.name)
                        if !loc.address.isEmpty {
                            previewRow(icon: "map",        label: "Address", value: loc.address)
                        }
                    }
                }

                if let em = payload.firstEmployeeEmail, !em.isEmpty {
                    previewSection(title: "First Employee") {
                        let name = [payload.firstEmployeeFirstName, payload.firstEmployeeLastName]
                            .compactMap { $0?.isEmpty == false ? $0 : nil }
                            .joined(separator: " ")
                        if !name.isEmpty {
                            previewRow(icon: "person", label: "Name", value: name)
                        }
                        previewRow(icon: "envelope", label: "Email", value: em)
                        if let role = payload.firstEmployeeRole {
                            previewRow(icon: "person.badge.key", label: "Role", value: role)
                        }
                    }
                }

                if let optIn = payload.sampleDataOptIn {
                    previewSection(title: "Sample Data") {
                        previewRow(
                            icon: optIn ? "sparkles" : "arrow.up.right.circle",
                            label: optIn ? "Will load demo data" : "Starting fresh",
                            value: nil
                        )
                    }
                }

                if payload.theme != "system" {
                    previewSection(title: "Theme") {
                        previewRow(icon: "paintbrush", label: "Appearance", value: payload.theme.capitalized)
                    }
                }

                Spacer(minLength: BrandSpacing.xxl)
            }
            .padding(BrandSpacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live preview of setup data")
    }

    // MARK: - Sub-views

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text("Preview")
                .font(.brandTitleLarge())
                .foregroundStyle(Color.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Text("Updates as you fill in each step")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
        .padding(.top, BrandSpacing.md)
    }

    @ViewBuilder
    private func previewSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                content()
            }
            .padding(BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.bizarreSurface1.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func previewRow(icon: String, label: String, value: String?) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.bizarreOrange)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .lineLimit(1)

            if let value, !value.isEmpty {
                Spacer(minLength: BrandSpacing.xxs)
                Text(value)
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { "\(label): \($0)" } ?? label)
    }
}
