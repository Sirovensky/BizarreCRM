import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - SmsComposerView

/// Full-screen SMS send view with dynamic-var chip bar, live preview,
/// character counter, and "Load template" button.
/// iPhone: full modal; iPad: shown as a sheet alongside the thread list.
public struct SmsComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SmsComposerViewModel
    @State private var showTemplatePicker = false
    @State private var isSending = false
    @State private var sendError: String?
    @FocusState private var composerFocused: Bool

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let onSend: (String, String) async throws -> Void // (to, body)

    public init(
        phoneNumber: String,
        prefillBody: String = "",
        api: APIClient,
        onSend: @escaping (String, String) async throws -> Void
    ) {
        _vm = State(wrappedValue: SmsComposerViewModel(
            phoneNumber: phoneNumber,
            prefillBody: prefillBody
        ))
        self.api = api
        self.onSend = onSend
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    scrollableContent
                    composerBar
                }
            }
            .navigationTitle("New Message")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarItems }
            .sheet(isPresented: $showTemplatePicker) { templatePicker }
        }
    }

    // MARK: - Scrollable content (preview + char info)

    private var scrollableContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                toField
                charCountRow
                if !vm.draft.isEmpty {
                    previewCard
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.md)
        }
    }

    private var toField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("To")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(vm.phoneNumber)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("To: \(vm.phoneNumber)")
    }

    private var charCountRow: some View {
        HStack {
            Text("\(vm.charCount) chars")
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(vm.smsSegmentCount == 0
                 ? "—"
                 : "\(vm.smsSegmentCount) segment\(vm.smsSegmentCount == 1 ? "" : "s")")
                .font(.brandMono(size: 12))
                .foregroundStyle(vm.smsSegmentCount > 2 ? .bizarreError : .bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.charCount) characters, \(vm.smsSegmentCount) SMS segments")
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Preview", systemImage: "eye")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(vm.livePreview)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Live preview: \(vm.livePreview)")
    }

    // MARK: - Bottom composer bar (chip bar + text field + send button)

    private var composerBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.bizarreOutline.opacity(0.4))
            // Chip bar — Liquid Glass on chrome
            chipBar
            Divider().overlay(Color.bizarreOutline.opacity(0.2))
            // Text field + send button
            HStack(alignment: .bottom, spacing: BrandSpacing.sm) {
                TextField("Message", text: $vm.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .frame(minHeight: 44)
                    .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                    .focused($composerFocused)
                    .lineLimit(1...6)
                    .accessibilityLabel("Message body")

                Button {
                    Task { await performSend() }
                } label: {
                    Image(systemName: isSending ? "ellipsis" : "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(
                            (!vm.isValid || isSending)
                                ? Color.bizarreOnSurfaceMuted
                                : Color.bizarreOrange,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!vm.isValid || isSending)
                .accessibilityLabel(isSending ? "Sending message" : "Send message")
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)

            if let err = sendError {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.xs)
                    .accessibilityLabel("Send error: \(err)")
            }
        }
        .background(Color.bizarreSurface1.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Send action

    @MainActor
    private func performSend() async {
        guard vm.isValid, !isSending else { return }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await onSend(vm.phoneNumber, vm.draft.trimmingCharacters(in: .whitespacesAndNewlines))
            vm.draft = ""
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(SmsComposerViewModel.knownVars, id: \.self) { chip in
                    Button {
                        vm.insertAtCursor(chip)
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
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
        .frame(height: 44)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel compose")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Templates") { showTemplatePicker = true }
                .font(.brandBodyMedium())
                .accessibilityLabel("Load a message template")
        }
    }

    // MARK: - Template picker sheet

    private var templatePicker: some View {
        NavigationStack {
            MessageTemplateListView(
                api: api,
                onPick: { template in
                    vm.loadTemplate(template)
                    showTemplatePicker = false
                }
            )
            .navigationTitle("Templates")
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
