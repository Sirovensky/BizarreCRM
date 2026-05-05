import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - EmailTemplateEditorViewModel

@MainActor
@Observable
public final class EmailTemplateEditorViewModel {

    // MARK: - Form fields

    public var name: String
    public var subject: String
    public var htmlBody: String
    public var category: EmailTemplateCategory

    // MARK: - State

    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public var selectedTab: EditorTab = .editor

    public enum EditorTab: String, CaseIterable {
        case editor = "Editor"
        case preview = "Preview"
    }

    // MARK: - Cursor (for subject chip insertion)

    public var subjectCursorOffset: Int?

    // MARK: - Derived

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !subject.trimmingCharacters(in: .whitespaces).isEmpty
            && !htmlBody.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var renderedPreview: EmailRenderer.Rendered {
        let template = EmailTemplate(
            id: existingId ?? 0,
            name: name,
            subject: subject,
            htmlBody: htmlBody,
            plainBody: nil,
            category: category,
            dynamicVars: []
        )
        return EmailRenderer.render(template: template, context: EmailRenderer.sampleContext)
    }

    public var extractedVars: [String] {
        let combined = subject + " " + htmlBody
        guard let regex = try? NSRegularExpression(pattern: "\\{[a-zA-Z_]+\\}") else { return [] }
        let range = NSRange(combined.startIndex..., in: combined)
        return Array(Set(regex.matches(in: combined, range: range).compactMap {
            Range($0.range, in: combined).map { String(combined[$0]) }
        }))
    }

    // MARK: - Known chips

    public static let knownVars: [String] = [
        "{first_name}", "{ticket_no}", "{total}", "{due_date}",
        "{tech_name}", "{appointment_time}", "{shop_name}"
    ]

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient?
    @ObservationIgnored let existingId: Int64?
    @ObservationIgnored private let onSave: (EmailTemplate) -> Void

    public init(
        template: EmailTemplate? = nil,
        api: APIClient?,
        onSave: @escaping (EmailTemplate) -> Void
    ) {
        self.api = api
        self.existingId = template?.id
        self.onSave = onSave
        name = template?.name ?? ""
        subject = template?.subject ?? ""
        htmlBody = template?.htmlBody ?? ""
        category = template?.category ?? .reminder
    }

    // MARK: - Insert chip into subject

    public func insertAtSubjectCursor(_ token: String) {
        let insertIndex: Int
        if let offset = subjectCursorOffset, offset >= 0, offset <= subject.count {
            insertIndex = offset
        } else {
            insertIndex = subject.count
        }
        let idx = subject.index(subject.startIndex, offsetBy: insertIndex)
        subject.insert(contentsOf: token, at: idx)
        subjectCursorOffset = insertIndex + token.count
    }

    // MARK: - Save

    public func save() async {
        guard isValid, let api else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let vars = extractedVars

        do {
            let saved: EmailTemplate
            if let id = existingId {
                saved = try await api.updateEmailTemplate(
                    id: id,
                    UpdateEmailTemplateRequest(
                        name: name.trimmingCharacters(in: .whitespaces),
                        subject: subject,
                        htmlBody: htmlBody,
                        plainBody: nil,
                        category: category,
                        dynamicVars: vars
                    )
                )
            } else {
                saved = try await api.createEmailTemplate(
                    CreateEmailTemplateRequest(
                        name: name.trimmingCharacters(in: .whitespaces),
                        subject: subject,
                        htmlBody: htmlBody,
                        plainBody: nil,
                        category: category,
                        dynamicVars: vars
                    )
                )
            }
            onSave(saved)
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.errorDescription
            AppLog.ui.error("Email template save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - EmailTemplateEditorView

public struct EmailTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EmailTemplateEditorViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(
        template: EmailTemplate? = nil,
        api: APIClient?,
        onSave: @escaping (EmailTemplate) -> Void
    ) {
        _vm = State(wrappedValue: EmailTemplateEditorViewModel(
            template: template,
            api: api,
            onSave: onSave
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if sizeClass == .regular {
                    iPadLayout
                } else {
                    iPhoneLayout
                }
            }
            .navigationTitle(vm.existingId == nil ? "New Email Template" : "Edit Email Template")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarItems }
        }
    }

    // MARK: - iPhone layout (tabbed)

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $vm.selectedTab) {
                ForEach(EmailTemplateEditorViewModel.EditorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.sm)

            if vm.selectedTab == .editor {
                editorForm
            } else {
                previewPane
            }
        }
    }

    // MARK: - iPad layout (side-by-side)

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            editorForm.frame(maxWidth: .infinity)
            Divider()
            previewPane.frame(maxWidth: .infinity)
        }
    }

    // MARK: - Editor form

    private var editorForm: some View {
        Form {
            metaSection
            subjectSection
            bodySection
            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var metaSection: some View {
        Section("Template info") {
            TextField("Template name", text: $vm.name)
                .accessibilityLabel("Template name — required")

            Picker("Category", selection: $vm.category) {
                ForEach(EmailTemplateCategory.allCases, id: \.self) { c in
                    Text(c.displayName).tag(c)
                }
            }
            .accessibilityLabel("Category selector")
        }
    }

    private var subjectSection: some View {
        Section("Subject") {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                TextField("Email subject", text: $vm.subject)
                    .accessibilityLabel("Email subject — required")

                // Subject chip bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(EmailTemplateEditorViewModel.knownVars, id: \.self) { chip in
                            Button {
                                vm.insertAtSubjectCursor(chip)
                            } label: {
                                Text(chip)
                                    .font(.brandMono(size: 11))
                                    .padding(.horizontal, BrandSpacing.sm)
                                    .padding(.vertical, BrandSpacing.xs)
                                    .foregroundStyle(.bizarreOnSurface)
                            }
                            .brandGlass(.regular, in: Capsule())
                            .accessibilityLabel("Insert \(chip) into subject")
                        }
                    }
                    .padding(.vertical, BrandSpacing.xs)
                }
            }
        }
    }

    private var bodySection: some View {
        Section("HTML Body") {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                // Body chip bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(EmailTemplateEditorViewModel.knownVars, id: \.self) { chip in
                            Button {
                                vm.htmlBody += chip
                            } label: {
                                Text(chip)
                                    .font(.brandMono(size: 11))
                                    .padding(.horizontal, BrandSpacing.sm)
                                    .padding(.vertical, BrandSpacing.xs)
                                    .foregroundStyle(.bizarreOnSurface)
                            }
                            .brandGlass(.regular, in: Capsule())
                            .accessibilityLabel("Insert \(chip) into body")
                        }
                    }
                    .padding(.vertical, BrandSpacing.xs)
                }

                TextEditor(text: $vm.htmlBody)
                    .frame(minHeight: 180)
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("HTML body — required")
            }
        }
    }

    // MARK: - Preview pane

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Subject: \(vm.renderedPreview.subject)")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.md)
                .accessibilityLabel("Preview subject: \(vm.renderedPreview.subject)")

            HtmlPreviewView(html: vm.renderedPreview.html)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.bizarreSurfaceBase)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel editing email template")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(vm.isSaving ? "Saving…" : "Save") {
                Task { await vm.save() }
            }
            .disabled(!vm.isValid || vm.isSaving)
            .accessibilityLabel(vm.isSaving ? "Saving template" : "Save email template")
        }
    }
}
