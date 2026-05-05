import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - HireWizardView
//
// §14.x Hire wizard: Manager → Team → Add employee.
// Steps: 1 Basic Info → 2 Role & Commission → 3 Access / Locations → 4 Welcome Email
//
// On step 4 "Finish", calls POST /api/v1/settings/users (CreateEmployeeBody).
// Server creates the account and (if SMTP is configured) sends a login link to
// the supplied email.  On self-hosted installs with no SMTP, the manager can
// share the login link manually.

// MARK: - Steps

enum HireWizardStep: Int, CaseIterable {
    case basicInfo    = 0
    case roleCommission = 1
    case access       = 2
    case welcomeEmail = 3
}

// MARK: - ViewModel

@MainActor
@Observable
public final class HireWizardViewModel {
    // Step tracking
    var currentStep: HireWizardStep = .basicInfo

    // Step 1 — Basic Info
    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""
    var phone: String = ""
    var username: String = ""

    // Step 2 — Role
    var selectedRole: String = "technician"
    var availableRoles: [String] = ["owner", "manager", "technician", "cashier", "receptionist", "accountant"]

    // Step 3 — Access (location IDs; future multi-location support)
    var accessAllLocations: Bool = true

    // Step 4 — Welcome email
    var sendWelcomeEmail: Bool = true

    // State
    var isSubmitting: Bool = false
    var errorMessage: String?
    var createdEmployeeId: Int64?
    var loginLink: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Derived username

    func updateDerivedUsername() {
        let base = (firstName.lowercased() + lastName.lowercased())
            .components(separatedBy: .whitespaces)
            .joined()
            .filter { $0.isLetter || $0.isNumber }
        username = base.isEmpty ? "" : base
    }

    // MARK: - Validation

    var canAdvanceFromBasicInfo: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Navigation

    func advance() {
        guard let next = HireWizardStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func back() {
        guard let prev = HireWizardStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    // MARK: - Submit

    func submit() async {
        isSubmitting = true
        errorMessage = nil
        let body = CreateEmployeeBody(
            username: username.trimmingCharacters(in: .whitespaces),
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces),
            role: selectedRole
        )
        do {
            let result = try await api.createEmployee(body: body)
            createdEmployeeId = result.id
            AppLog.ui.info("Hire wizard: created employee id=\(result.id, privacy: .public)")
        } catch {
            AppLog.ui.error("Hire wizard submit: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - HireWizardView

public struct HireWizardView: View {
    @State private var vm: HireWizardViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient) {
        _vm = State(wrappedValue: HireWizardViewModel(api: api))
    }

    init(viewModel: HireWizardViewModel) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    stepIndicator
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.top, BrandSpacing.md)
                    Divider().padding(.top, BrandSpacing.sm)
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    navigationButtons
                        .padding(BrandSpacing.lg)
                }
            }
            .navigationTitle("Add Team Member")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: BrandSpacing.sm) {
            ForEach(HireWizardStep.allCases, id: \.self) { step in
                stepDot(step)
                if step != .welcomeEmail {
                    Rectangle()
                        .fill(vm.currentStep.rawValue > step.rawValue ? Color.bizarreOrange : Color.bizarreOutline)
                        .frame(height: 2)
                        .animation(BrandMotion.snappy, value: vm.currentStep)
                }
            }
        }
    }

    private func stepDot(_ step: HireWizardStep) -> some View {
        let done = vm.currentStep.rawValue > step.rawValue
        let current = vm.currentStep == step
        return ZStack {
            Circle()
                .fill(done || current ? Color.bizarreOrange : Color.bizarreOutline)
                .frame(width: 28, height: 28)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(step.rawValue + 1)")
                    .font(.brandLabelSmall().bold())
                    .foregroundStyle(current ? .white : .bizarreOnSurfaceMuted)
            }
        }
        .animation(BrandMotion.snappy, value: vm.currentStep)
        .accessibilityLabel("Step \(step.rawValue + 1)\(done ? " completed" : current ? " current" : "")")
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                switch vm.currentStep {
                case .basicInfo:    basicInfoStep
                case .roleCommission: roleStep
                case .access:       accessStep
                case .welcomeEmail: welcomeStep
                }
            }
            .padding(BrandSpacing.lg)
        }
    }

    // Step 1
    private var basicInfoStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            stepHeader(title: "Basic Information", subtitle: "Enter the new team member's details.")
            formField("First Name", text: $vm.firstName, required: true)
                .onChange(of: vm.firstName) { _, _ in vm.updateDerivedUsername() }
            formField("Last Name", text: $vm.lastName, required: true)
                .onChange(of: vm.lastName) { _, _ in vm.updateDerivedUsername() }
            formField("Username", text: $vm.username, required: true)
            formField("Email (optional)", text: $vm.email, keyboard: .emailAddress)
            footerNote("Email is optional on self-hosted installs. Without email the welcome link must be shared manually.")
        }
    }

    // Step 2
    private var roleStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            stepHeader(title: "Role", subtitle: "Assign an initial role. You can change it later.")
            Picker("Role", selection: $vm.selectedRole) {
                ForEach(vm.availableRoles, id: \.self) { role in
                    Text(role.capitalized).tag(role)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 160)
            footerNote("Commission rules can be configured in Settings → Team → Commission Rules after the account is created.")
        }
    }

    // Step 3
    private var accessStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            stepHeader(title: "Access & Locations", subtitle: "Choose which locations this employee can access.")
            Toggle("Access All Locations", isOn: $vm.accessAllLocations)
                .tint(.bizarreOrange)
            if !vm.accessAllLocations {
                footerNote("Multi-location per-employee restrictions will be configurable here once location setup is complete.")
            }
        }
    }

    // Step 4
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            stepHeader(title: "Welcome Email", subtitle: "Send a login link to the new team member.")
            Toggle("Send welcome email", isOn: $vm.sendWelcomeEmail)
                .tint(.bizarreOrange)
                .disabled(vm.email.isEmpty)
            if vm.email.isEmpty {
                footerNote("No email address was provided — the welcome link must be shared manually from the employee's profile after creation.")
            }
            if let err = vm.errorMessage {
                Text(err)
                    .foregroundStyle(.bizarreError)
                    .font(.brandBodyMedium())
            }
            if let id = vm.createdEmployeeId {
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    Label("Account created!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.brandTitleSmall())
                    Text("Employee ID: \(id)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Navigation buttons

    private var navigationButtons: some View {
        HStack {
            if vm.currentStep != .basicInfo {
                Button("Back") { vm.back() }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOnSurface)
                    .accessibilityIdentifier("hire.back")
            }
            Spacer(minLength: BrandSpacing.md)
            if vm.currentStep == .welcomeEmail {
                if vm.createdEmployeeId == nil {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create Account")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .disabled(vm.isSubmitting)
                    .accessibilityIdentifier("hire.submit")
                } else {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .accessibilityIdentifier("hire.done")
                }
            } else {
                Button("Next") { vm.advance() }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .disabled(vm.currentStep == .basicInfo && !vm.canAdvanceFromBasicInfo)
                    .accessibilityIdentifier("hire.next")
            }
        }
    }

    // MARK: - Helpers

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title).font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private func formField(
        _ label: String,
        text: Binding<String>,
        required: Bool = false,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(spacing: 2) {
                Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                if required { Text("*").foregroundStyle(.bizarreError).font(.brandLabelSmall()) }
            }
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .accessibilityLabel(label + (required ? ", required" : ""))
        }
    }

    private func footerNote(_ text: String) -> some View {
        Text(text)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .padding(.horizontal, BrandSpacing.sm)
    }
}

// MARK: - API extension

public extension APIClient {
    /// `POST /api/v1/settings/users` — create a new employee account (admin only).
    func createEmployee(body: CreateEmployeeBody) async throws -> CreatedEmployeeResult {
        try await post(
            "/api/v1/settings/users",
            body: body,
            as: CreatedEmployeeResult.self
        )
    }
}

public struct CreatedEmployeeResult: Decodable, Sendable {
    public let id: Int64
    public let username: String?
    public let loginLink: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case loginLink = "login_link"
    }
}
