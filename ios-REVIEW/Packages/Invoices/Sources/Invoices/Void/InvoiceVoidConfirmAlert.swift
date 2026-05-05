#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §7.5 Void Confirm Alert — destructive confirmation + reason field

/// Presents a destructive alert with a mandatory reason field.
/// Use `.invoiceVoidAlert(isPresented:vm:onSuccess:)` modifier on any view.
public struct InvoiceVoidAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var vm: InvoiceVoidViewModel
    @State private var showReasonSheet: Bool = false
    let onSuccess: (VoidResult) -> Void

    public init(isPresented: Binding<Bool>, vm: InvoiceVoidViewModel, onSuccess: @escaping (VoidResult) -> Void) {
        _isPresented = isPresented
        _vm = State(wrappedValue: vm)
        self.onSuccess = onSuccess
    }

    public func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, new in
                if new { showReasonSheet = true; isPresented = false }
            }
            .sheet(isPresented: $showReasonSheet) {
                VoidReasonSheet(vm: vm) { result in
                    onSuccess(result)
                    showReasonSheet = false
                } onCancel: {
                    showReasonSheet = false
                }
            }
            .onChange(of: vm.state) { _, newState in
                if case let .success(result) = newState {
                    onSuccess(result)
                    showReasonSheet = false
                }
            }
    }
}

public extension View {
    func invoiceVoidAlert(
        isPresented: Binding<Bool>,
        vm: InvoiceVoidViewModel,
        onSuccess: @escaping (VoidResult) -> Void
    ) -> some View {
        modifier(InvoiceVoidAlertModifier(isPresented: isPresented, vm: vm, onSuccess: onSuccess))
    }
}

// MARK: - Void Reason Sheet

private struct VoidReasonSheet: View {
    @State private var vm: InvoiceVoidViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSuccess: (VoidResult) -> Void
    let onCancel: () -> Void

    init(vm: InvoiceVoidViewModel, onSuccess: @escaping (VoidResult) -> Void, onCancel: @escaping () -> Void) {
        _vm = State(wrappedValue: vm)
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.xl) {
                    VStack(spacing: BrandSpacing.md) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.bizarreError)

                        Text("Void Invoice?")
                            .font(.brandHeadlineMedium())
                            .foregroundStyle(.bizarreOnSurface)

                        Text("This action is irreversible. The invoice will be marked void and no further payments can be collected.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BrandSpacing.lg)
                    }

                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        Text("Reason (required)")
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)

                        TextField("Enter reason for voiding this invoice", text: $vm.reason, axis: .vertical)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .lineLimit(3...)
                            .padding(BrandSpacing.sm)
                            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1))
                            .accessibilityLabel("Void reason — required")
                    }
                    .padding(.horizontal, BrandSpacing.base)

                    if case let .failed(msg) = vm.state {
                        Text(msg)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .padding(.horizontal, BrandSpacing.base)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: BrandSpacing.sm) {
                        Button {
                            Task { await vm.submitVoid() }
                        } label: {
                            Group {
                                if case .submitting = vm.state {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Void Invoice")
                                        .font(.brandTitleMedium())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BrandSpacing.md)
                        }
                        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm), tint: .bizarreError, interactive: true)
                        .foregroundStyle(.white)
                        .disabled(!vm.isValid || {
                            if case .submitting = vm.state { return true }
                            return false
                        }())
                        .accessibilityLabel("Confirm void invoice")

                        Button("Cancel", role: .cancel) { onCancel() }
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOrange)
                    }
                    .padding(.horizontal, BrandSpacing.base)

                    Spacer()
                }
                .padding(.top, BrandSpacing.xl)
            }
            .navigationTitle("Void Invoice")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}
#endif
