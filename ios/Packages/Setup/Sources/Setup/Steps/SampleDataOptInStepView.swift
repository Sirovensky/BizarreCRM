import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - SampleDataOptInStepView  (§36 — sample data opt-in)
//
// Lets the admin choose to pre-load demo customers/tickets/invoices so the
// app looks populated on day 1. The actual POST goes to
//   /api/v1/onboarding/sample-data (server: routes/onboarding.routes.ts)
//
// Design: two large radio-style cards (Yes / No) + live count preview when
// the user hovers "Yes". Loads cleanly on both iPhone and iPad (the step body
// is embedded in the split layout on iPad via SetupWizardView).

@MainActor
@Observable
final class SampleDataOptInViewModel {

    enum Choice: Equatable {
        case yes, no
    }

    var choice: Choice? = nil
    var isLoading: Bool = false
    var loadError: String? = nil
    var loadedCounts: SampleDataCountsDisplay? = nil

    var isNextEnabled: Bool { choice != nil }

    struct SampleDataCountsDisplay: Sendable {
        let customers: Int
        let tickets: Int
        let invoices: Int
    }
}

public struct SampleDataOptInStepView: View {

    let onValidityChanged: (Bool) -> Void
    let onNext: (Bool) -> Void

    @State private var vm = SampleDataOptInViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (Bool) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                headerSection
                optionCards
                if vm.choice == .yes {
                    previewBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: BrandSpacing.xxl)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.lg)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: vm.choice)
        .onChange(of: vm.isNextEnabled) { _, valid in
            onValidityChanged(valid)
        }
        .onAppear {
            onValidityChanged(vm.isNextEnabled)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Sample Data")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Text("Start with demo customers, tickets, and invoices to explore the app — or jump in fresh.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Option Cards

    private var optionCards: some View {
        VStack(spacing: BrandSpacing.md) {
            optionCard(
                choice: .yes,
                icon: "sparkles",
                title: "Load sample data",
                subtitle: "5 customers · 10 tickets · 3 invoices  (removable any time)"
            )
            optionCard(
                choice: .no,
                icon: "arrow.up.right.circle",
                title: "Start fresh",
                subtitle: "Begin with a clean slate — add real data as you go"
            )
        }
    }

    @ViewBuilder
    private func optionCard(
        choice: SampleDataOptInViewModel.Choice,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = vm.choice == choice

        Button {
            vm.choice = choice
            onValidityChanged(true) // a choice was made, so valid
            // Eagerly surface the selected value up to the wizard so
            // wizardPayload.sampleDataOptIn is set before submitCurrentStep().
            onNext(choice == .yes)
        } label: {
            HStack(spacing: BrandSpacing.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.bizarreOrange : Color.bizarreSurface1.opacity(0.6))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Color.bizarreOnSurface)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(title)
                        .font(.brandTitleSmall())
                        .foregroundStyle(Color.bizarreOnSurface)
                    Text(subtitle)
                        .font(.brandBodySmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOutline)
                    .accessibilityHidden(true)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                        value: isSelected
                    )
            }
            .padding(BrandSpacing.md)
            .background(
                isSelected
                    ? Color.bizarreOrange.opacity(0.10)
                    : Color.bizarreSurface1.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.4),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Preview Banner

    private var previewBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.bizarreTeal)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Demo data will be visible with a [Sample] tag")
                    .font(.brandBodySmall())
                    .foregroundStyle(Color.bizarreOnSurface)
                Text("You can remove it any time from Settings → Onboarding")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.bizarreTeal.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
