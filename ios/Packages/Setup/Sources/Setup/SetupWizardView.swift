import SwiftUI
import Core
import DesignSystem

// MARK: - SetupWizardView
// §36 Shell — adaptive layout:
//   iPhone (width < 600pt)  : full-screen vertical flow (indicator → form → navBar)
//   iPad   (width ≥ 900pt)  : three-pane split — sidebar | form | live preview
//   iPad   (600–899pt)      : two-pane — sidebar | form (no preview column)
// All chrome uses Liquid Glass via .brandGlass.

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
                contentLayout(proxy: proxy)
            }
        }
        .task { await vm.loadServerState() }
    }

    // MARK: - Adaptive layout dispatcher

    @ViewBuilder
    private func contentLayout(proxy: GeometryProxy) -> some View {
        let w = proxy.size.width
        if w < 600 {
            // iPhone — full-screen vertical
            iPhoneLayout
        } else if w < 900 {
            // Small iPad — sidebar + form, no preview
            iPadTwoPaneLayout
        } else {
            // Full iPad — sidebar + form + live preview
            iPadThreePaneLayout
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            indicatorBar
            stepBody
            navBar
        }
    }

    // MARK: - iPad two-pane (sidebar | form)

    private var iPadTwoPaneLayout: some View {
        HStack(spacing: 0) {
            stepSidebar
                .frame(width: 220)
                .brandGlass(.regular, in: Rectangle())

            Divider()

            VStack(spacing: 0) {
                stepBody
                navBar
            }
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(BrandSpacing.xl)
    }

    // MARK: - iPad three-pane (sidebar | form | live preview)

    private var iPadThreePaneLayout: some View {
        HStack(spacing: 0) {
            stepSidebar
                .frame(width: 220)
                .brandGlass(.regular, in: Rectangle())

            Divider()

            VStack(spacing: 0) {
                stepBody
                navBar
            }
            .frame(minWidth: 380, maxWidth: 500)

            Divider()

            SetupLivePreview(payload: vm.wizardPayload, currentStep: vm.currentStep)
                .frame(minWidth: 280)
                .brandGlass(.regular, in: Rectangle())
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(BrandSpacing.xl)
    }

    // MARK: - Step sidebar (iPad only)

    private var stepSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Setup")
                    .font(.brandTitleLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.top, BrandSpacing.lg)
                    .padding(.bottom, BrandSpacing.md)
                    .accessibilityAddTraits(.isHeader)

                ForEach(SetupStep.allCases.filter { $0 != .complete }, id: \.rawValue) { step in
                    sidebarRow(step)
                }
            }
            .padding(.bottom, BrandSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityLabel("Setup steps")
    }

    @ViewBuilder
    private func sidebarRow(_ step: SetupStep) -> some View {
        let isCurrent   = step == vm.currentStep
        let isCompleted = vm.completedSteps.contains(step.rawValue)

        HStack(spacing: BrandSpacing.sm) {
            ZStack {
                Circle()
                    .fill(isCurrent  ? Color.bizarreOrange :
                          isCompleted ? Color.bizarreTeal   : Color.bizarreOutline.opacity(0.3))
                    .frame(width: 22, height: 22)
                if isCompleted && !isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isCurrent ? .white : Color.bizarreOnSurface)
                }
            }
            .accessibilityHidden(true)

            Text(step.title)
                .font(.brandLabelLarge())
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? Color.bizarreOrange : Color.bizarreOnSurface)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(
            isCurrent ? Color.bizarreOrange.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .padding(.horizontal, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityLabel("\(step.title)\(isCompleted ? ", completed" : "")\(isCurrent ? ", current step" : "")")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .hoverEffect(.highlight)
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

        case .firstEmployee:
            FirstEmployeeStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { payload in
                    if let p = payload {
                        vm.wizardPayload.firstEmployeeFirstName = p.firstName
                        vm.wizardPayload.firstEmployeeLastName  = p.lastName
                        vm.wizardPayload.firstEmployeeEmail     = p.email
                        vm.wizardPayload.firstEmployeeRole      = p.role.rawValue
                    } else {
                        vm.wizardPayload.firstEmployeeFirstName = nil
                        vm.wizardPayload.firstEmployeeLastName  = nil
                        vm.wizardPayload.firstEmployeeEmail     = nil
                        vm.wizardPayload.firstEmployeeRole      = nil
                    }
                    Task { await vm.goNext() }
                }
            )

        case .smsSetup:
            SmsSetupStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { provider, fromNumber in
                    vm.wizardPayload.smsProvider    = provider == .skip ? nil : provider.rawValue
                    vm.wizardPayload.smsFromNumber  = fromNumber
                    Task { await vm.goNext() }
                }
            )

        case .deviceTemplates:
            DeviceTemplatesStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { families in
                    vm.wizardPayload.enabledDeviceFamilies = Set(families.map(\.rawValue))
                    Task { await vm.goNext() }
                }
            )

        case .dataImport:
            ImportDataStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { source in
                    if source == .skip {
                        vm.wizardPayload.skipImport  = true
                        vm.wizardPayload.importSource = nil
                    } else {
                        vm.wizardPayload.skipImport  = false
                        vm.wizardPayload.importSource = source.rawValue
                    }
                    Task { await vm.goNext() }
                }
            )

        case .theme:
            ThemeStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { themeChoice in
                    vm.wizardPayload.theme = themeChoice.rawValue
                    Task { await vm.goNext() }
                }
            )

        case .sampleData:
            SampleDataOptInStepView(
                onValidityChanged: { valid in stepValid = valid },
                onNext: { optIn in
                    vm.wizardPayload.sampleDataOptIn = optIn
                    Task { await vm.goNext() }
                }
            )

        case .complete:
            DoneStepView(
                completedSteps: vm.completedSteps,
                onOpenDashboard: {
                    Task { await vm.goNext() }
                }
            )
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
