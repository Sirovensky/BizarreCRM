import SwiftUI
import Core
import DesignSystem

// MARK: - SetupLivePreviewPane  (§22 iPad polish)
//
// iPad-optimised live-preview wrapper for the 3-col wizard layout.
// Renders a richer, larger version of the compact SetupLivePreview:
//   - Prominent header with animated progress ring
//   - Grouped data cards with more generous spacing
//   - Step-aware banner indicating what the current step will fill in next
//
// This lives in the right column (≥ 300 pt) of SetupThreeColumnView.
// It receives a reactive SetupPayload and the active step for contextual hints.

public struct SetupLivePreviewPane: View {

    // MARK: - Properties

    public let payload: SetupPayload
    public let currentStep: SetupStep

    // MARK: - Init

    public init(payload: SetupPayload, currentStep: SetupStep) {
        self.payload = payload
        self.currentStep = currentStep
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                headerSection
                stepHintBanner
                dataCards
                Spacer(minLength: BrandSpacing.xxl)
            }
            .padding(BrandSpacing.base)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live preview of setup data")
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            progressRing
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Preview")
                    .font(.brandTitleLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Text("Updates as you go")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(.top, BrandSpacing.md)
    }

    // MARK: - Progress ring

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.bizarreOutline.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    Color.bizarreOrange,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progressFraction)
            Text("\(Int(progressFraction * 100))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.bizarreOrange)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Setup \(Int(progressFraction * 100)) percent complete")
    }

    // MARK: - Step-aware hint banner

    @ViewBuilder
    private var stepHintBanner: some View {
        if let hint = currentStepHint {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)
                Text(hint)
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.bizarreOrange.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.25), value: currentStep)
        }
    }

    // MARK: - Data cards

    @ViewBuilder
    private var dataCards: some View {
        if payload.companyName.isEmpty &&
           payload.timezone == nil &&
           payload.taxRate == nil &&
           payload.paymentMethods == [.cash] &&
           payload.firstLocation == nil &&
           payload.firstEmployeeEmail == nil &&
           payload.sampleDataOptIn == nil {
            emptyStateCard
        } else {
            filledDataCards
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 36))
                .foregroundStyle(Color.bizarreOutline.opacity(0.4))
                .accessibilityHidden(true)
            Text("Your setup data will appear here as you fill in each step.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xxl)
    }

    @ViewBuilder
    private var filledDataCards: some View {
        if !payload.companyName.isEmpty {
            PreviewDataCard(title: "Business", icon: "building.2") {
                PreviewDataRow(icon: "building.2", label: "Name",    value: payload.companyName)
                if !payload.companyAddress.isEmpty {
                    PreviewDataRow(icon: "map",         label: "Address", value: payload.companyAddress)
                }
                if !payload.companyPhone.isEmpty {
                    PreviewDataRow(icon: "phone",        label: "Phone",   value: payload.companyPhone)
                }
            }
        }

        if let tz = payload.timezone {
            PreviewDataCard(title: "Locale", icon: "globe") {
                PreviewDataRow(icon: "clock",              label: "Timezone", value: tz)
                if let cu = payload.currency {
                    PreviewDataRow(icon: "dollarsign.circle", label: "Currency", value: cu)
                }
                if let lo = payload.locale {
                    PreviewDataRow(icon: "globe",              label: "Locale",   value: lo)
                }
            }
        }

        if let tax = payload.taxRate {
            PreviewDataCard(title: "Tax", icon: "percent") {
                PreviewDataRow(icon: "percent", label: tax.name,      value: "\(String(format: "%.2f", tax.ratePct))%")
                PreviewDataRow(icon: "tag",     label: "Applies to",  value: tax.applyTo.displayName)
            }
        }

        if !payload.paymentMethods.isEmpty {
            PreviewDataCard(title: "Payments", icon: "creditcard") {
                ForEach(
                    payload.paymentMethods.sorted(by: { $0.rawValue < $1.rawValue }),
                    id: \.rawValue
                ) { method in
                    PreviewDataRow(icon: method.systemImage, label: method.displayName, value: nil)
                }
            }
        }

        if let loc = payload.firstLocation {
            PreviewDataCard(title: "Location", icon: "storefront") {
                PreviewDataRow(icon: "storefront", label: "Name",    value: loc.name)
                if !loc.address.isEmpty {
                    PreviewDataRow(icon: "map",        label: "Address", value: loc.address)
                }
            }
        }

        if let em = payload.firstEmployeeEmail, !em.isEmpty {
            PreviewDataCard(title: "First Employee", icon: "person") {
                let name = [payload.firstEmployeeFirstName, payload.firstEmployeeLastName]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " ")
                if !name.isEmpty {
                    PreviewDataRow(icon: "person",      label: "Name",  value: name)
                }
                PreviewDataRow(icon: "envelope",    label: "Email", value: em)
                if let role = payload.firstEmployeeRole {
                    PreviewDataRow(icon: "person.badge.key", label: "Role", value: role)
                }
            }
        }

        if let theme = Optional(payload.theme), theme != "system" {
            PreviewDataCard(title: "Theme", icon: "paintbrush") {
                PreviewDataRow(icon: "paintbrush", label: "Appearance", value: theme.capitalized)
            }
        }

        if let optIn = payload.sampleDataOptIn {
            PreviewDataCard(title: "Sample Data", icon: optIn ? "sparkles" : "arrow.up.right.circle") {
                PreviewDataRow(
                    icon: optIn ? "sparkles" : "arrow.up.right.circle",
                    label: optIn ? "Will load demo data" : "Starting fresh",
                    value: nil
                )
            }
        }
    }

    // MARK: - Computed helpers

    private var progressFraction: Double {
        let total = Double(SetupStep.totalCount - 1)
        guard total > 0 else { return 0 }
        return Double(currentStep.rawValue - 1) / total
    }

    private var currentStepHint: String? {
        switch currentStep {
        case .welcome:         return "Enter your company details to get started."
        case .companyInfo:     return "Your company name and address will appear here."
        case .logo:            return "Your logo will be displayed in invoices and emails."
        case .timezoneLocale:  return "Timezone and currency settings will show here."
        case .businessHours:   return "Business hours help set expectations with customers."
        case .taxSetup:        return "Tax rate will be pre-filled on invoices."
        case .paymentMethods:  return "Accepted payment methods will appear on receipts."
        case .firstLocation:   return "Your first location will show here."
        case .firstEmployee:   return "Your first team member's info will appear here."
        case .smsSetup:        return "SMS settings enable automated customer messages."
        case .deviceTemplates: return "Device families determine your service templates."
        case .dataImport:      return "Migrate existing customers and inventory."
        case .theme:           return "Choose a look that fits your brand."
        case .sampleData:      return "Sample data lets you explore before going live."
        case .complete:        return nil
        }
    }
}

// MARK: - PreviewDataCard

struct PreviewDataCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                content
            }
            .padding(BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.bizarreSurface1.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }
}

// MARK: - PreviewDataRow

struct PreviewDataRow: View {
    let icon: String
    let label: String
    let value: String?

    var body: some View {
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
