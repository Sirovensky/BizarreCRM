import SwiftUI
import Core
import DesignSystem

// MARK: - SetupWizardView
// §36.1 Shell: iPhone = .fullScreenCover, iPad = .sheet centered, max-width 720pt, glass card.

public struct SetupWizardView: View {
    @State private var vm: SetupWizardViewModel
    @State private var stepValid: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(repository: any SetupRepository) {
        _vm = State(wrappedValue: SetupWizardViewModel(repository: repository))
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                contentCard(proxy: proxy)
            }
        }
        .task { await vm.loadServerState() }
    }

    // MARK: - Card layout

    @ViewBuilder
    private func contentCard(proxy: GeometryProxy) -> some View {
        let isCompact = proxy.size.width < 600
        if isCompact {
            VStack(spacing: 0) {
                indicatorBar
                stepBody
                navBar
            }
        } else {
            VStack(spacing: 0) {
                indicatorBar
                stepBody
                navBar
            }
            .frame(maxWidth: 720)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(BrandSpacing.xxl)
        }
    }

    // MARK: - Step indicator chip

    private var indicatorBar: some View {
        HStack {
            Spacer()
            SetupStepIndicator(
                currentStep: vm.currentStep,
                completedSteps: vm.completedSteps
            )
            Spacer()
        }
        .padding(.top, BrandSpacing.base)
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Active step body

    @ViewBuilder
    private var stepBody: some View {
        ZStack {
            activeStepView
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
                .animation(vm.isSaving ? nil : (reduceMotion ? .easeInOut(duration: 0.15) : BrandMotion.sheet), value: vm.currentStep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if vm.isSaving {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                }
            }
        }
        .overlay(alignment: .top) {
            if let msg = vm.errorMessage {
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.white)
                    .padding(BrandSpacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(Color.bizarreError, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.errorMessage)
    }

    @ViewBuilder
    private var activeStepView: some View {
        switch vm.currentStep {
        case .welcome:
            WelcomeStepView(onGetStarted: {
                Task { await vm.goNext() }
            }, onSkip: {
                vm.deferWizard()
            })

        case .companyInfo:
            CompanyInfoStepView(onValidityChanged: { valid in
                stepValid = valid
            }, onNext: { payload in
                vm.pendingPayload = payload
                // Mirror into wizardPayload for cross-step pre-fill
                vm.wizardPayload.companyName    = payload["name"]    ?? ""
                vm.wizardPayload.companyAddress = payload["address"] ?? ""
                vm.wizardPayload.companyPhone   = payload["phone"]   ?? ""
                Task { await vm.goNext() }
            })

        case .logo:
            LogoStepView(repository: vm.repository,
                         onNext: { url in
                vm.pendingPayload = url.map { ["logoUrl": $0] } ?? [:]
                Task { await vm.goNext() }
            })

        case .timezoneLocale:
            TimezoneLocaleStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { tz, currency, locale in
                    vm.wizardPayload.timezone = tz
                    vm.wizardPayload.currency = currency
                    vm.wizardPayload.locale   = locale
                    Task { await vm.goNext() }
                }
            )

        case .businessHours:
            BusinessHoursStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { days in
                    vm.wizardPayload.hours = days
                    Task { await vm.goNext() }
                }
            )

        case .taxSetup:
            TaxSetupStepView(
                companyAddress: vm.wizardPayload.companyAddress,
                onValidityChanged: { valid in stepValid = valid },
                onNext: { taxRate in
                    vm.wizardPayload.taxRate = taxRate
                    Task { await vm.goNext() }
                }
            )

        case .paymentMethods:
            PaymentMethodsStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { methods in
                    vm.wizardPayload.paymentMethods = methods
                    Task { await vm.goNext() }
                }
            )

        case .firstLocation:
            FirstLocationStepView(
                companyName:    vm.wizardPayload.companyName,
                companyAddress: vm.wizardPayload.companyAddress,
                companyPhone:   vm.wizardPayload.companyPhone,
                onValidityChanged: { valid in stepValid = valid },
                onNext: { location in
                    vm.wizardPayload.firstLocation = location
                    Task { await vm.goNext() }
                }
            )

        default:
            PlaceholderStepView(step: vm.currentStep)
        }
    }

    // MARK: - Navigation bar (glass)

    private var navBar: some View {
        HStack(spacing: BrandSpacing.md) {
            if vm.canGoBack {
                Button {
                    vm.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.brandLabelLarge())
                }
                .buttonStyle(.brandGlass)
                .accessibilityLabel("Go back to \(vm.currentStep.previous?.title ?? "previous step")")
            }

            Spacer()

            Button {
                if vm.currentStep == .welcome {
                    vm.deferWizard()
                } else {
                    Task { await vm.skipStep() }
                }
            } label: {
                Text(vm.currentStep == .welcome ? "Do Later" : "Skip")
                    .font(.brandLabelLarge())
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel(vm.currentStep == .welcome ? "Dismiss setup and do later" : "Skip this step")

            Button {
                Task { await vm.goNext() }
            } label: {
                Text(vm.isOnLastStep ? "Finish" : "Next")
                    .font(.brandTitleSmall())
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(!stepValid || vm.isSaving)
            .accessibilityLabel(vm.isOnLastStep ? "Finish setup" : "Continue to \(vm.currentStep.next?.title ?? "next step")")
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.regular, in: Rectangle())
    }
}

// MARK: - Presentation helper

public extension View {
    @MainActor
    func setupWizard(isPresented: Binding<Bool>, repository: any SetupRepository) -> some View {
        modifier(SetupWizardPresenter(isPresented: isPresented, repository: repository))
    }
}

@MainActor
private struct SetupWizardPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let repository: any SetupRepository
    @Environment(\.horizontalSizeClass) private var hSizeClass

    func body(content: Content) -> some View {
        #if os(iOS)
        if hSizeClass == .compact {
            content.fullScreenCover(isPresented: $isPresented) {
                SetupWizardView(repository: repository)
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                SetupWizardView(repository: repository)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
        #else
        content.sheet(isPresented: $isPresented) {
            SetupWizardView(repository: repository)
                .presentationDetents([.large])
        }
        #endif
    }
}
