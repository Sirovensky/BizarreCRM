import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class PaymentMethodsViewModel {
    var enabledMethods: Set<PaymentMethod> = [.cash]

    var isNextEnabled: Bool {
        Step7Validator.isNextEnabled(methods: enabledMethods)
    }

    func toggle(_ method: PaymentMethod) {
        if enabledMethods.contains(method) {
            enabledMethods.remove(method)
        } else {
            enabledMethods.insert(method)
        }
    }

    func isEnabled(_ method: PaymentMethod) -> Bool {
        enabledMethods.contains(method)
    }
}

// MARK: - View  (§36.2 Step 7 — Payment Methods)

@MainActor
public struct PaymentMethodsStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: (Set<PaymentMethod>) -> Void

    @State private var vm = PaymentMethodsViewModel()

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (Set<PaymentMethod>) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                Text("Payment Methods")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.top, BrandSpacing.lg)
                    .accessibilityAddTraits(.isHeader)

                Text("Choose how your shop accepts payment. You can change these later in Settings.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)

                VStack(spacing: 0) {
                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                        MethodRow(
                            method: method,
                            isEnabled: vm.isEnabled(method),
                            onToggle: { vm.toggle(method) }
                        )
                        if method != PaymentMethod.allCases.last {
                            Divider()
                                .background(Color.bizarreOutline.opacity(0.3))
                        }
                    }
                }
                .background(
                    Color.bizarreSurface1.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1)
                )

                if !vm.isNextEnabled {
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.bizarreError)
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text("Enable at least one payment method to continue.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(Color.bizarreError)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(.easeInOut(duration: 0.15), value: vm.isNextEnabled)
        .onChange(of: vm.isNextEnabled) { _, valid in
            onValidityChanged(valid)
        }
        .onAppear {
            onValidityChanged(vm.isNextEnabled)
        }
    }
}

// MARK: - MethodRow

@MainActor
private struct MethodRow: View {
    let method: PaymentMethod
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(get: { isEnabled }, set: { _ in onToggle() })) {
                HStack(spacing: BrandSpacing.md) {
                    Image(systemName: method.systemImage)
                        .foregroundStyle(isEnabled ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(method.displayName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(isEnabled ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)

                        if method == .card && isEnabled {
                            Text("You can pair your BlockChyp terminal later from Settings.")
                                .font(.brandLabelSmall())
                                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(.bizarreOrange)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .accessibilityLabel(method.displayName)
            .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
            .accessibilityHint(method == .card && isEnabled
                ? "BlockChyp terminal pairing available later in Settings"
                : "")
        }
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
    }
}
