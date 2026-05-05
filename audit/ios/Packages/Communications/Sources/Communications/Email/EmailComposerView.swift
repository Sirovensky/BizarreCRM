import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EmailComposerView

/// Full-screen email composer.
/// iPhone: modal; iPad: side-by-side form + HTML preview.
public struct EmailComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EmailComposerViewModel
    @State private var showTemplatePicker = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    @ObservationIgnored private let api: APIClient

    public init(
        toEmail: String,
        prefillSubject: String = "",
        prefillBody: String = "",
        api: APIClient
    ) {
        self.api = api
        _vm = State(wrappedValue: EmailComposerViewModel(
            toEmail: toEmail,
            prefillSubject: prefillSubject,
            prefillBody: prefillBody,
            api: api
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
            .navigationTitle("New Email")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarItems }
            .sheet(isPresented: $showTemplatePicker) { templatePickerSheet }
            .onChange(of: vm.didSend) { _, sent in
                if sent { dismiss() }
            }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                formFields
                chipBarSection(label: "Insert variable")
                if !vm.body.isEmpty {
                    previewSection
                }
                sendButton
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.md)
        }
    }

    // MARK: - iPad layout (side-by-side)

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    formFields
                    chipBarSection(label: "Insert variable")
                    sendButton
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.md)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("HTML Preview")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.leading, BrandSpacing.base)
                    .padding(.top, BrandSpacing.md)
                HtmlPreviewView(html: vm.htmlPreview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared sub-views

    private var formFields: some View {
        VStack(spacing: BrandSpacing.md) {
            // To
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("To").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("Recipient email", text: $vm.toEmail)
                    #if os(iOS)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    #endif
                    .accessibilityLabel("To — recipient email address")
            }

            // Subject
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Subject").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("Subject line", text: $vm.subject)
                    .accessibilityLabel("Subject line")
            }

            // Body
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Body").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                TextEditor(text: $vm.body)
                    .frame(minHeight: 180)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Email body — HTML")
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Error: \(err)")
            }
        }
    }

    private func chipBarSection(label: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(EmailComposerViewModel.knownVars, id: \.self) { chip in
                        Button {
                            vm.insertAtBodyCursor(chip)
                        } label: {
                            Text(chip)
                                .font(.brandMono(size: 12))
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        .brandGlass(.regular, in: Capsule())
                        .accessibilityLabel("Insert \(chip)")
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("HTML Preview (sample data)", systemImage: "eye")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HtmlPreviewView(html: vm.htmlPreview)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("HTML email preview with sample data")
        }
    }

    private var sendButton: some View {
        Button {
            Task { await vm.send() }
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                if vm.isSending {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(vm.isSending ? "Sending…" : "Send Email")
                    .font(.brandBodyMedium().bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .disabled(!vm.isValid || vm.isSending)
        .accessibilityLabel(vm.isSending ? "Sending email" : "Send email")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel composing email")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Templates") { showTemplatePicker = true }
                .accessibilityLabel("Load an email template")
        }
    }

    // MARK: - Template picker

    private var templatePickerSheet: some View {
        NavigationStack {
            EmailTemplateListView(
                api: api,
                onPick: { template in
                    vm.loadTemplate(template)
                    showTemplatePicker = false
                }
            )
            .navigationTitle("Email Templates")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTemplatePicker = false }
                }
            }
        }
    }
}
