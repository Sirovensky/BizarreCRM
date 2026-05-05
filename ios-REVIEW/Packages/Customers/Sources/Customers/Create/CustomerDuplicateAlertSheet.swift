#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5.3 Duplicate detection alert sheet

/// Sheet presented before save when the duplicate checker finds a candidate.
///
/// Options:
///  - "Use existing" — dismiss create form, caller navigates to existing customer.
///  - "Create anyway" — proceed with save ignoring the match.
///  - "Cancel" — abort; user can adjust the form.
public struct CustomerDuplicateAlertSheet: View {
    let candidate: CustomerSummary
    let onUseExisting: (CustomerSummary) -> Void
    let onCreateAnyway: () -> Void

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    // Icon
                    Image(systemName: "person.2.badge.gearshape")
                        .font(.system(size: 48))
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityHidden(true)

                    VStack(spacing: BrandSpacing.sm) {
                        Text("Possible Duplicate")
                            .font(.brandHeadlineMedium())
                            .foregroundStyle(.bizarreOnSurface)

                        Text("This might be the same person as:")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .multilineTextAlignment(.center)

                    // Candidate card
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        HStack(spacing: BrandSpacing.md) {
                            ZStack {
                                Circle().fill(Color.bizarreOrangeContainer)
                                Text(candidate.initials)
                                    .font(.brandTitleSmall())
                                    .foregroundStyle(.bizarreOnOrange)
                            }
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                Text(candidate.displayName)
                                    .font(.brandBodyLarge())
                                    .foregroundStyle(.bizarreOnSurface)
                                if let phone = candidate.mobile ?? candidate.phone, !phone.isEmpty {
                                    Text(PhoneFormatter.format(phone))
                                        .font(.brandLabelLarge())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .textSelection(.enabled)
                                }
                                if let email = candidate.email, !email.isEmpty {
                                    Text(email)
                                        .font(.brandLabelLarge())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .textSelection(.enabled)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(BrandSpacing.base)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))

                    // Action buttons
                    VStack(spacing: BrandSpacing.sm) {
                        Button {
                            dismiss()
                            onUseExisting(candidate)
                        } label: {
                            Text("Use Existing Customer")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Use existing customer \(candidate.displayName)")

                        Button {
                            dismiss()
                            onCreateAnyway()
                        } label: {
                            Text("Create Anyway")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.bizarreOnSurface)
                        .accessibilityLabel("Create new customer anyway, ignoring the duplicate")

                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("Cancel and go back to form")
                    }

                    Spacer(minLength: 0)
                }
                .padding(BrandSpacing.lg)
            }
            .navigationTitle("Duplicate Found")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
#endif
