import SwiftUI
import Core
import DesignSystem
import Networking
import Observation

// MARK: - BugReportCategory

public enum BugReportCategory: String, CaseIterable, Sendable {
    case crash          = "Crash"
    case uiBug          = "UI Bug"
    case dataIssue      = "Data Issue"
    case performance    = "Performance"
    case featureRequest = "Feature Request"
}

// MARK: - BugReportSeverity

public enum BugReportSeverity: String, CaseIterable, Sendable {
    case low      = "Low"
    case medium   = "Medium"
    case high     = "High"
    case critical = "Critical"
}

// MARK: - BugReportViewModel

@MainActor
@Observable
public final class BugReportViewModel {

    // MARK: - Form fields

    public var description: String = ""
    public var category: BugReportCategory = .uiBug
    public var severity: BugReportSeverity = .medium

    // MARK: - State

    public private(set) var isSubmitting: Bool = false
    public private(set) var submissionResult: SubmissionResult?
    public private(set) var validationError: String?

    // MARK: - Types

    public enum SubmissionResult: Equatable, Sendable {
        case success(ticketID: String)
        case failure(message: String)
    }

    // MARK: - Dependencies

    private let api: (any APIClient)?
    private let diagnosticsBuilder: DiagnosticsBundleBuilder

    // MARK: - Init

    public init(
        api: (any APIClient)? = APIClientHolder.current,
        diagnosticsBuilder: DiagnosticsBundleBuilder = DiagnosticsBundleBuilder()
    ) {
        self.api = api
        self.diagnosticsBuilder = diagnosticsBuilder
    }

    // MARK: - Validation

    public var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Submit

    public func submit() async {
        validationError = nil
        guard isValid else {
            validationError = "Please enter a description."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let bundle = await diagnosticsBuilder.build()
        let payload = BugReportPayload(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.rawValue,
            severity: severity.rawValue,
            appVersion: bundle.appVersion,
            iosVersion: bundle.iosVersion,
            deviceModel: bundle.deviceModel
        )

        do {
            guard let api else {
                submissionResult = .failure(message: "Not connected to a server.")
                return
            }
            let response = try await api.post(
                "/support/bug-reports",
                body: payload,
                as: BugReportResponse.self
            )
            submissionResult = .success(ticketID: response.ticketID ?? "")
        } catch {
            submissionResult = .failure(message: error.localizedDescription)
        }
    }

    // MARK: - Reset

    public func reset() {
        description = ""
        category = .uiBug
        severity = .medium
        validationError = nil
        submissionResult = nil
    }
}

// MARK: - API models

private struct BugReportPayload: Encodable, Sendable {
    let description: String
    let category: String
    let severity: String
    let appVersion: String
    let iosVersion: String
    let deviceModel: String
}

private struct BugReportResponse: Decodable, Sendable {
    let ticketID: String?
    enum CodingKeys: String, CodingKey { case ticketID = "ticketId" }
}

// MARK: - BugReportSheet

/// Bug report form: description, category, severity; auto-attached diagnostics bundle.
public struct BugReportSheet: View {

    @State private var vm: BugReportViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: BugReportViewModel = BugReportViewModel()) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            Form {
                descriptionSection
                categorySection
                severitySection
                diagnosticsNote
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Report a Bug")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel bug report")
                }
                ToolbarItem(placement: .confirmationAction) {
                    submitButton
                }
            }
            .overlay { resultOverlay }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    @ViewBuilder
    private var descriptionSection: some View {
        Section {
            TextEditor(text: $vm.description)
                .frame(minHeight: 100)
                .accessibilityLabel("Bug description")
                .accessibilityHint("Required. Describe what went wrong.")
            if let err = vm.validationError {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        } header: {
            Text("Description *")
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("Required. Describe what you expected and what happened.")
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        Section("Category") {
            Picker("Category", selection: $vm.category) {
                ForEach(BugReportCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Bug category: \(vm.category.rawValue)")
        }
    }

    @ViewBuilder
    private var severitySection: some View {
        Section("Severity") {
            Picker("Severity", selection: $vm.severity) {
                ForEach(BugReportSeverity.allCases, id: \.self) { sev in
                    Text(sev.rawValue).tag(sev)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Severity: \(vm.severity.rawValue)")
        }
    }

    @ViewBuilder
    private var diagnosticsNote: some View {
        Section {
            Label("Device info and last 20 redacted log entries will be attached automatically.", systemImage: "info.circle")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Submit button

    @ViewBuilder
    private var submitButton: some View {
        if vm.isSubmitting {
            ProgressView()
                .accessibilityLabel("Submitting bug report")
        } else {
            Button("Submit") {
                Task { await vm.submit() }
            }
            .disabled(!vm.isValid)
            .accessibilityLabel("Submit bug report")
            .accessibilityHint(vm.isValid ? "Sends your report" : "Enter a description first")
        }
    }

    // MARK: - Result overlay

    @ViewBuilder
    private var resultOverlay: some View {
        if let result = vm.submissionResult {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: BrandSpacing.base) {
                        switch result {
                        case .success(let id):
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.bizarreSuccess)
                                .accessibilityHidden(true)
                            Text(id.isEmpty ? "Report submitted!" : "Thanks — ticket \(id) created.")
                                .font(.brandHeadlineMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .multilineTextAlignment(.center)
                        case .failure(let msg):
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.bizarreError)
                                .accessibilityHidden(true)
                            Text("Submission failed")
                                .font(.brandHeadlineMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text(msg)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .multilineTextAlignment(.center)
                        }
                        Button("Done") {
                            if case .success = result { dismiss() }
                            else { vm.reset() }
                        }
                        .padding(.horizontal, BrandSpacing.xl)
                        .padding(.vertical, BrandSpacing.sm)
                        .brandGlass(.regular, in: Capsule(), tint: .bizarreOrange, interactive: true)
                        .accessibilityLabel("Done")
                    }
                    .padding(BrandSpacing.xl)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 20))
                    .padding(BrandSpacing.xl)
                }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    BugReportSheet()
}
#endif
