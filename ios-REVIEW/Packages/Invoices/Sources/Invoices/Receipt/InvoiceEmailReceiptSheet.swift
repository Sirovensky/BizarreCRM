#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.6 Email Receipt Sheet (View only — ViewModel in InvoiceEmailReceiptViewModel.swift)

public struct InvoiceEmailReceiptSheet: View {
    @State private var vm: InvoiceEmailReceiptViewModel
    @Environment(\.dismiss) private var dismiss

    let onSuccess: () -> Void

    public init(vm: InvoiceEmailReceiptViewModel, onSuccess: @escaping () -> Void) {
        _vm = State(wrappedValue: vm)
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        emailSection
                        messageSection
                        smsToggle
                        sendButton
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Email Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.bizarreOrange)
                }
            }
            .toolbarBackground(.bizarreSurface1, for: .navigationBar)
            .onChange(of: vm.state) { _, newState in
                if case .success = newState {
                    onSuccess()
                    dismiss()
                }
            }
            .alert("Send Error", isPresented: .constant({
                if case .failed = vm.state { return true }
                return false
            }()), actions: {
                Button("OK") { vm.resetToIdle() }
            }, message: {
                if case let .failed(msg) = vm.state { Text(msg) }
            })
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.large])
    }

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Email Address")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            TextField("customer@example.com", text: $vm.emailAddress)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Recipient email address")
        }
        .cardBackground()
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Message (optional)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            TextField("Add a personal note...", text: $vm.message, axis: .vertical)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(4...)
                .accessibilityLabel("Optional message to include with receipt")
        }
        .cardBackground()
    }

    private var smsToggle: some View {
        Toggle(isOn: $vm.sendSmsCopy) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Also send SMS copy")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let phone = vm.customerPhone, !phone.isEmpty {
                    Text(phone)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .tint(.bizarreOrange)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityLabel("Send SMS copy toggle")
    }

    private var sendButton: some View {
        Button {
            Task { await vm.send() }
        } label: {
            Group {
                if case .sending = vm.state {
                    ProgressView().tint(.white)
                } else {
                    Text("Send Receipt")
                        .font(.brandTitleMedium())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), tint: .bizarreOrange, interactive: true)
        .foregroundStyle(.white)
        .disabled(!vm.isValid || {
            if case .sending = vm.state { return true }
            return false
        }())
        .accessibilityLabel("Send email receipt")
    }
}

// MARK: - Helpers

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}
#endif
