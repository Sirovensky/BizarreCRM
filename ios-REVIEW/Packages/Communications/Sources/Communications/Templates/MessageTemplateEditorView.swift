import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - MessageTemplateEditorViewModel

@MainActor
@Observable
public final class MessageTemplateEditorViewModel {

    // MARK: - Form fields

    public var name: String
    public var body: String
    public var channel: MessageChannel
    public var category: MessageTemplateCategory

    // MARK: - State

    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var savedTemplate: MessageTemplate?

    // MARK: - Preview

    public var livePreview: String {
        TemplateRenderer.render(body, variables: .sample)
    }

    public var extractedVars: [String] {
        TemplateRenderer.extractVariables(from: body)
    }

    // MARK: - Validation

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !body.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient?
    @ObservationIgnored private let existingId: Int64?
    @ObservationIgnored private let onSave: (MessageTemplate) -> Void

    public init(
        template: MessageTemplate? = nil,
        api: APIClient?,
        onSave: @escaping (MessageTemplate) -> Void
    ) {
        self.api = api
        self.existingId = template?.id
        self.onSave = onSave
        name = template?.name ?? ""
        body = template?.body ?? ""
        channel = template?.channel ?? .sms
        category = template?.category ?? .reminder
    }

    // MARK: - Save

    public func save() async {
        guard isValid, let api else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let saved: MessageTemplate
            if let id = existingId {
                saved = try await api.updateMessageTemplate(
                    id: id,
                    UpdateMessageTemplateRequest(
                        name: name.trimmingCharacters(in: .whitespaces),
                        body: body,
                        channel: channel,
                        category: category
                    )
                )
            } else {
                saved = try await api.createMessageTemplate(
                    CreateMessageTemplateRequest(
                        name: name.trimmingCharacters(in: .whitespaces),
                        body: body,
                        channel: channel,
                        category: category
                    )
                )
            }
            savedTemplate = saved
            onSave(saved)
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.errorDescription
            AppLog.ui.error("Template save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - MessageTemplateEditorView

public struct MessageTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: MessageTemplateEditorViewModel

    private static let knownVars = ["{first_name}", "{last_name}", "{ticket_no}", "{company}", "{amount}", "{date}"]

    public init(
        template: MessageTemplate? = nil,
        api: APIClient?,
        onSave: @escaping (MessageTemplate) -> Void
    ) {
        _vm = State(wrappedValue: MessageTemplateEditorViewModel(
            template: template,
            api: api,
            onSave: onSave
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    nameSection
                    channelCategorySection
                    bodySection
                    dynamicVarSection
                    previewSection
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
            .navigationTitle(vm.existingIdIsNil ? "New Template" : "Edit Template")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel editing template")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task { await vm.save() }
                    }
                    .disabled(!vm.isValid || vm.isSaving)
                    .accessibilityLabel(vm.isSaving ? "Saving template" : "Save template")
                }
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Template name", text: $vm.name)
                .accessibilityLabel("Template name — required")
        }
    }

    private var channelCategorySection: some View {
        Section("Channel & Category") {
            Picker("Channel", selection: $vm.channel) {
                ForEach(MessageChannel.allCases, id: \.self) { c in
                    Text(c.rawValue.capitalized).tag(c)
                }
            }
            .accessibilityLabel("Channel selector")

            Picker("Category", selection: $vm.category) {
                ForEach(MessageTemplateCategory.allCases, id: \.self) { c in
                    Text(c.displayName).tag(c)
                }
            }
            .accessibilityLabel("Category selector")
        }
    }

    private var bodySection: some View {
        Section("Body") {
            TextEditor(text: $vm.body)
                .frame(minHeight: 100)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Template body text")
        }
    }

    private var dynamicVarSection: some View {
        Section("Insert variable") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(Self.knownVars, id: \.self) { v in
                        Button {
                            vm.body += v
                        } label: {
                            Text(v)
                                .font(.brandMono(size: 12))
                                .padding(.horizontal, BrandSpacing.sm)
                                .padding(.vertical, BrandSpacing.xs)
                                .foregroundStyle(.bizarreOnSurface)
                                .background(Color.bizarreSurface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Insert variable \(v)")
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
            .listRowInsets(EdgeInsets(
                top: 0, leading: BrandSpacing.md,
                bottom: 0, trailing: BrandSpacing.md
            ))
        }
    }

    private var previewSection: some View {
        Section("Preview (sample data)") {
            Text(vm.livePreview)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("Template preview: \(vm.livePreview)")
        }
    }

    // MARK: - Helper

    private var existingIdIsNil: Bool { vm.existingIdIsNil }
}

extension MessageTemplateEditorViewModel {
    var existingIdIsNil: Bool { existingId == nil }
}
