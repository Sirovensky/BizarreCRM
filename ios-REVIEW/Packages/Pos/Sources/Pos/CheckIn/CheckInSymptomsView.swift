/// CheckInSymptomsView.swift — §16.25.1
///
/// Step 1: Symptom selection. 4×2 grid of symptom tiles with multi-select.
/// Minimum 1 symptom to advance. "Other" expands a free-text field.
///
/// Spec: mockup frame "CI-1 · Symptoms · tap what's broken".

#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - Symptom tile model

private struct SymptomTile: Identifiable {
    let id: String
    let label: String
    let icon: String
}

private let allSymptoms: [SymptomTile] = [
    .init(id: "crackedScreen",  label: "Cracked screen",  icon: "iphone.gen3"),
    .init(id: "batteryDrain",   label: "Battery drain",   icon: "battery.25"),
    .init(id: "wontCharge",     label: "Won't charge",    icon: "bolt.slash"),
    .init(id: "liquidDamage",   label: "Liquid damage",   icon: "drop"),
    .init(id: "noSound",        label: "No sound",        icon: "speaker.slash"),
    .init(id: "camera",         label: "Camera",          icon: "camera"),
    .init(id: "buttons",        label: "Buttons",         icon: "button.horizontal"),
    .init(id: "other",          label: "Other",           icon: "exclamationmark.triangle"),
]

// MARK: - CheckInSymptomsView

struct CheckInSymptomsView: View {
    @Bindable var draft: CheckInDraft
    @FocusState private var otherFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // Instruction
                Text("What's broken?")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.bizarreOnSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.md)

                // 4×2 tile grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: BrandSpacing.sm),
                        GridItem(.flexible(), spacing: BrandSpacing.sm),
                    ],
                    spacing: BrandSpacing.sm
                ) {
                    ForEach(allSymptoms) { symptom in
                        symptomTile(symptom)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Select symptoms — tap all that apply")

                // "Other" free-text expansion
                if draft.symptoms.contains("other") {
                    TextField("Describe the issue…", text: $draft.symptomOtherText, axis: .vertical)
                        .focused($otherFocused)
                        .padding(BrandSpacing.md)
                        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .strokeBorder(Color.bizarreOrange.opacity(0.4), lineWidth: 0.5)
                        )
                        .padding(.horizontal, BrandSpacing.base)
                        .onAppear { otherFocused = true }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // Footer hint
                Text("Next: customer notes, photos, passcode")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.base)
            }
            .padding(.bottom, BrandSpacing.xl)
        }
        .animation(.easeOut(duration: 0.2), value: draft.symptoms)
    }

    private func symptomTile(_ symptom: SymptomTile) -> some View {
        let isSelected = draft.symptoms.contains(symptom.id)
        return Button {
            BrandHaptics.tap()
            withAnimation(.easeOut(duration: 0.15)) {
                draft.toggleSymptom(symptom.id)
            }
        } label: {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: symptom.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                Text(NSLocalizedString("checkin.symptoms.\(symptom.id)", value: symptom.label, comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                            .strokeBorder(
                                isSelected ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.4),
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityLabel("\(symptom.label), \(isSelected ? "selected" : "not selected")")
    }
}
#endif
