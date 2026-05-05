import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class SmsSetupViewModel {

    // MARK: State

    var provider: SmsProvider = .skip
    var fromNumber: String = ""
    var confirmationTemplate: String = "default_confirmation"
    var reminderTemplate: String    = "default_reminder"
    var readyTemplate: String       = "default_ready"
    var testSendNumber: String = ""
    var isTesting: Bool = false
    var testResult: String? = nil

    // MARK: Validation

    var fromNumberError: String? = nil

    var isNextEnabled: Bool {
        Step10Validator.isNextEnabled(fromNumber: fromNumber, provider: provider)
    }

    func onFromNumberBlur() {
        let r = Step10Validator.validateFromNumber(fromNumber, provider: provider)
        fromNumberError = r.isValid ? nil : r.errorMessage
    }

    func onProviderChanged() {
        fromNumberError = nil
    }

    // MARK: Test send (stub — wired through SetupRepository in production)

    func sendTest() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        // Simulate network call; real impl would call repository.testSmsSend(...)
        try? await Task.sleep(nanoseconds: 500_000_000)
        testResult = "Test message sent to \(testSendNumber)."
    }
}

// MARK: - View  (§36.2 Step 10 — SMS Setup)

@MainActor
public struct SmsSetupStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: (SmsProvider, String?) -> Void

    @State private var vm = SmsSetupViewModel()
    @FocusState private var focus: Field?

    enum Field: Hashable { case fromNumber, testNumber }

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (SmsProvider, String?) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                header

                providerPicker

                if vm.provider != .skip {
                    fromNumberField
                    templatePickers
                    testSendSection
                }

                if vm.provider == .skip {
                    skipNote
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { onValidityChanged(vm.isNextEnabled) }
        .onChange(of: vm.isNextEnabled) { _, valid in onValidityChanged(valid) }
        .onChange(of: vm.provider) { _, _ in vm.onProviderChanged() }
    }

    // MARK: Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("SMS Setup")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.top, BrandSpacing.lg)
                .accessibilityAddTraits(.isHeader)

            Text("Connect an SMS provider to send appointment confirmations, reminders and status updates.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Provider")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            ForEach(SmsProvider.allCases, id: \.self) { provider in
                providerRow(provider)
            }
        }
    }

    private func providerRow(_ provider: SmsProvider) -> some View {
        Button {
            vm.provider = provider
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: vm.provider == provider ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(vm.provider == provider ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(provider.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                Spacer()
            }
            .padding(BrandSpacing.md)
            .background(
                vm.provider == provider
                    ? Color.bizarreOrange.opacity(0.1)
                    : Color.bizarreSurface1.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        vm.provider == provider ? Color.bizarreOrange.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.displayName)
        .accessibilityValue(vm.provider == provider ? "Selected" : "")
        .accessibilityAddTraits(vm.provider == provider ? [.isSelected] : [])
    }

    private var fromNumberField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("From Number")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            TextField("+1 (555) 000-0000", text: $vm.fromNumber)
                .font(.brandBodyLarge())
                .focused($focus, equals: .fromNumber)
                .submitLabel(.next)
                .onChange(of: focus) { (old: Field?, new: Field?) in
                    if old == .fromNumber && new != .fromNumber { vm.onFromNumberBlur() }
                }
                .padding(BrandSpacing.md)
                .background(
                    Color.bizarreSurface1.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            vm.fromNumberError != nil ? Color.bizarreError : Color.bizarreOutline.opacity(0.5),
                            lineWidth: 1
                        )
                )
                .accessibilityLabel("From number")
                .accessibilityHint("The phone number your customers will see messages from")
            #if canImport(UIKit)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            #endif

            if let err = vm.fromNumberError {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreError)
                    .accessibilityLabel("Error: \(err)")
            }

            Button {
                // Opens SMS number purchase URL
            } label: {
                Label("Buy a number", systemImage: "plus.circle")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOrange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buy a new phone number")
        }
        .animation(.easeInOut(duration: 0.15), value: vm.fromNumberError)
    }

    private var templatePickers: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Message Templates")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            templateRow(label: "Confirmation", selection: $vm.confirmationTemplate)
            templateRow(label: "Reminder",     selection: $vm.reminderTemplate)
            templateRow(label: "Ready for Pickup", selection: $vm.readyTemplate)
        }
    }

    private func templateRow(label: String, selection: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurface)
            Spacer()
            // In production this would drive a sheet with a template list
            Text(selection.wrappedValue.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .padding(BrandSpacing.md)
        .background(
            Color.bizarreSurface1.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityLabel("\(label) template: \(selection.wrappedValue)")
        .accessibilityHint("Tap to change the \(label.lowercased()) message template")
    }

    private var testSendSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Test Send")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            HStack(spacing: BrandSpacing.sm) {
                TextField("Mobile number", text: $vm.testSendNumber)
                    .font(.brandBodyLarge())
                    .focused($focus, equals: .testNumber)
                    .submitLabel(.send)
                    .onSubmit { Task { await vm.sendTest() } }
                    .padding(BrandSpacing.md)
                    .background(
                        Color.bizarreSurface1.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1)
                    )
                    .accessibilityLabel("Test send phone number")
                #if canImport(UIKit)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                #endif

                Button {
                    Task { await vm.sendTest() }
                } label: {
                    Group {
                        if vm.isTesting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Send")
                                .font(.brandLabelLarge())
                        }
                    }
                    .frame(width: 60, height: 44)
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .disabled(vm.testSendNumber.isEmpty || vm.isTesting)
                .accessibilityLabel("Send test SMS")
            }

            if let result = vm.testResult {
                Text(result)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreSuccess)
                    .accessibilityLabel(result)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.testResult)
    }

    private var skipNote: some View {
        Text("You can set up SMS later from Settings → Communications.")
            .font(.brandBodyMedium())
            .foregroundStyle(Color.bizarreOnSurfaceMuted)
            .padding(BrandSpacing.md)
            .background(
                Color.bizarreSurface1.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}
