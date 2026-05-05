#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.2 Send invoice by SMS sheet — pre-fills "Your invoice: {payment-link-url}".
// Cross-platform: iPhone shows .medium/.large detent; iPad shows .large.

public struct InvoiceSMSSheet: View {
    @State private var vm: InvoiceSMSViewModel
    @Environment(\.dismiss) private var dismiss

    let onSuccess: () -> Void

    public init(vm: InvoiceSMSViewModel, onSuccess: @escaping () -> Void) {
        _vm = State(wrappedValue: vm)
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        phoneSection
                        messageSection
                        sendButton
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Send Invoice by SMS")
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
            .alert("Send Failed", isPresented: .constant({
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

    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Phone number")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            TextField("e.g. +1 555 000 0000", text: $vm.phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Recipient phone number")
        }
        .cardBackground()
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Message")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            TextField("Message to customer", text: $vm.messageBody, axis: .vertical)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(4...)
                .accessibilityLabel("SMS message body")
        }
        .cardBackground()
    }

    private var sendButton: some View {
        Button {
            Task { await vm.send() }
        } label: {
            Group {
                if case .sending = vm.state {
                    ProgressView().tint(.white)
                } else {
                    Text("Send SMS")
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
        .accessibilityLabel("Send SMS to customer")
    }
}

// MARK: - Card helper

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
