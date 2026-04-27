#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §2.5 Manager override: reset staff PIN

/// Presented by a manager to reset a staff member's PIN.
///
/// The manager enters their own PIN to authorize the reset, which invalidates
/// the staff member's current PIN and sends them an email reset link.
///
/// Usage (within a manager-only settings area or staff roster):
/// ```swift
/// ManagerPinResetView(staffUserId: id, staffName: name, api: apiClient)
/// ```
public struct ManagerPinResetView: View {

    @State private var viewModel: ManagerPinResetViewModel
    @Environment(\.dismiss) private var dismiss

    public init(staffUserId: String, staffName: String, api: APIClient) {
        _viewModel = State(wrappedValue: ManagerPinResetViewModel(
            staffUserId: staffUserId,
            staffName: staffName,
            api: api
        ))
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            header

            Text("Enter your manager PIN to reset \(viewModel.staffName)'s PIN. They will receive an email with a link to set a new PIN.")
                .font(.brandBodySmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isDone {
                successSection
            } else {
                managerPinSection
            }

            if let error = viewModel.errorMessage {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.bizarreError)
                        .imageScale(.small)
                    Text(error)
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreError)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .padding(.bottom, BrandSpacing.base)
        }
        .padding(BrandSpacing.xxxl)
        .navigationTitle("Reset Staff PIN")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 40))
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)

            Text("Reset PIN for \(viewModel.staffName)")
                .font(.brandTitleLarge())
                .foregroundStyle(Color.bizarreOnSurface)
                .multilineTextAlignment(.center)
        }
        .padding(.top, BrandSpacing.xxxl)
    }

    private var managerPinSection: some View {
        VStack(spacing: BrandSpacing.md) {
            SecureField("Your manager PIN", text: $viewModel.managerPin)
                .keyboardType(.numberPad)
                .onChange(of: viewModel.managerPin) { _, new in
                    viewModel.managerPin = String(new.filter(\.isNumber).prefix(6))
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
                .privacySensitive()
                .accessibilityLabel("Manager PIN")

            Button {
                Task { await viewModel.resetStaffPin() }
            } label: {
                HStack {
                    if viewModel.isSubmitting {
                        ProgressView().tint(Color.bizarreOnOrange)
                    }
                    Text("Reset PIN")
                        .font(.brandTitleMedium().bold())
                }
            }
            .buttonStyle(.brandGlassProminent)
            .tint(Color.bizarreOrange)
            .foregroundStyle(Color.bizarreOnOrange)
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("managerPinReset.submit")
        }
    }

    private var successSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.bizarreSuccess)

            Text("PIN reset email sent.")
                .font(.brandTitleMedium().bold())
                .foregroundStyle(Color.bizarreOnSurface)

            Text("\(viewModel.staffName) will receive an email with a link to set a new PIN.")
                .font(.brandBodySmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PIN reset email sent to \(viewModel.staffName).")
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ManagerPinResetViewModel {

    let staffUserId: String
    let staffName: String

    var managerPin: String = ""
    var isSubmitting = false
    var isDone = false
    var errorMessage: String? = nil

    private let api: APIClient

    var canSubmit: Bool { managerPin.count >= 4 && !isSubmitting }

    init(staffUserId: String, staffName: String, api: APIClient) {
        self.staffUserId = staffUserId
        self.staffName = staffName
        self.api = api
    }

    func resetStaffPin() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await api.managerPinReset(staffUserId: staffUserId, managerPin: managerPin)
            isDone = true
        } catch {
            errorMessage = "Could not reset the PIN. Check your manager PIN and try again."
        }
        isSubmitting = false
    }
}

#endif
