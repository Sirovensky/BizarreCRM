#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - §2.5 Change PIN — Settings → Security

/// Lets an authenticated user replace their device-local PIN.
///
/// **Integration:**
/// ```swift
/// NavigationLink("Change PIN") {
///     ChangePINView(api: apiClient)
/// }
/// ```
public struct ChangePINView: View {

    @State private var viewModel: ChangePINViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient) {
        self._viewModel = State(wrappedValue: ChangePINViewModel(api: api))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // §2.13 — PIN fields carry `.privacySensitive()` so they are
                // redacted on the app-switcher and any screenshot recorded when
                // the app backgrounds.
                pinField("Current PIN", text: $viewModel.currentPIN)
                    .privacySensitive()

                pinField("New PIN (4–6 digits)", text: $viewModel.newPIN)
                    .privacySensitive()

                pinField("Confirm new PIN", text: $viewModel.confirmPIN)
                    .privacySensitive()

                if viewModel.mismatch {
                    mismatchWarning
                }

                if let err = viewModel.errorMessage {
                    errorRow(err)
                }

                if let ok = viewModel.successMessage {
                    successRow(ok)
                }

                submitButton
            }
            .padding(BrandSpacing.lg)
        }
        .navigationTitle("Change PIN")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        // Dismiss after a brief success-state delay so the user sees the toast.
        .onChange(of: viewModel.successMessage) { _, new in
            guard new != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            }
        }
    }

    // MARK: - Private views

    private func pinField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            SecureField("Digits only", text: text)
                .keyboardType(.numberPad)
                .onChange(of: text.wrappedValue) { _, new in
                    text.wrappedValue = String(new.filter(\.isNumber).prefix(6))
                }
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.base)
                .frame(minHeight: 52)
                .background(Color.bizarreSurface2.opacity(0.7),
                             in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5)
                )
        }
    }

    private var mismatchWarning: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.bizarreWarning)
                .imageScale(.small)
            Text("PINs don't match yet.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreWarning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
            Text(message)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreError)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("changePIN.error")
    }

    private func successRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreSuccess)
            Text(message)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreSuccess)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("changePIN.success")
    }

    private var submitButton: some View {
        Button {
            Task { await viewModel.submit() }
        } label: {
            HStack {
                if viewModel.isSubmitting {
                    ProgressView().tint(.bizarreOnOrange)
                }
                Text("Update PIN")
                    .font(.brandTitleMedium()).bold()
            }
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .foregroundStyle(.bizarreOnOrange)
        .disabled(!viewModel.canSubmit)
        .accessibilityIdentifier("changePIN.submit")
    }
}

#endif
