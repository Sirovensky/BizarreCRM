#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

struct PosCustomerPickerUnavailable: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("Customer directory unavailable")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Sign in and reconnect to search existing customers.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Attach customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

enum PosCustomerNameFormatter {
    static func displayName(firstName: String, lastName: String, fallback: String = "") -> String {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !joined.isEmpty { return joined }
        let org = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return org.isEmpty ? "Customer" : org
    }

    static func attachPayload(
        id: Int64,
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        mobile: String,
        organization: String
    ) -> PosCustomer {
        let name = displayName(firstName: firstName, lastName: lastName, fallback: organization)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMobile = mobile.trimmingCharacters(in: .whitespacesAndNewlines)
        let pickPhone = trimmedMobile.isEmpty ? trimmedPhone : trimmedMobile
        return PosCustomer(
            id: id,
            displayName: name,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            phone: pickPhone.isEmpty ? nil : pickPhone
        )
    }
}
#endif
