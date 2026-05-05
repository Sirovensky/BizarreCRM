import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - SmsComposerInlineBar

/// iPad-specific inline composer bar docked at the bottom of the conversation
/// column (detail column of `SmsThreeColumnView`).
///
/// Design rules:
///   - Liquid Glass on the bar chrome (`.brandGlass`) — NOT on the text field bubble.
///   - Dynamic-var chip scroll bar above the text row.
///   - Send button disabled while draft is empty or sending.
///   - Character + segment counter badge on the right of the chip bar.
///   - Does NOT push a new view — stays inline with the conversation.
///
/// When `targetPhone` is nil the bar shows a "To:" field so it can be used
/// as a standalone new-thread composer (e.g. from the ⌘N sheet).
public struct SmsComposerInlineBar: View {
    // MARK: Dependencies
    private let api: APIClient
    private let repo: SmsRepository
    private let onSend: (String, String) async throws -> Void

    // MARK: State
    @State private var vm: SmsComposerViewModel
    @State private var toPhone: String
    @State private var isSending: Bool = false
    @State private var sendError: String?
    @State private var showTemplatePicker: Bool = false
    @FocusState private var composerFocused: Bool

    /// When set, the bar sends to this phone number and hides the "To:" field.
    private let targetPhone: String?

    // MARK: Init

    /// Composer attached to an existing thread (targetPhone known).
    public init(
        api: APIClient,
        repo: SmsRepository,
        targetPhone: String,
        onSend: @escaping (String, String) async throws -> Void
    ) {
        self.api = api
        self.repo = repo
        self.targetPhone = targetPhone
        self.onSend = onSend
        _vm = State(wrappedValue: SmsComposerViewModel(phoneNumber: targetPhone))
        _toPhone = State(wrappedValue: targetPhone)
    }

    /// Freeform new-thread composer (targetPhone unknown — user types a number).
    public init(
        api: APIClient,
        repo: SmsRepository,
        onSend: @escaping (String, String) async throws -> Void
    ) {
        self.api = api
        self.repo = repo
        self.targetPhone = nil
        self.onSend = onSend
        _vm = State(wrappedValue: SmsComposerViewModel(phoneNumber: ""))
        _toPhone = State(wrappedValue: "")
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.bizarreOutline.opacity(0.4))
            chipBar
            Divider()
                .overlay(Color.bizarreOutline.opacity(0.2))
            inputRow
            errorRow
        }
        .brandGlass(.regular, in: Rectangle())
        .sheet(isPresented: $showTemplatePicker) {
            templatePickerSheet
        }
    }

    // MARK: - Chip bar (dynamic variables + segment counter)

    private var chipBar: some View {
        HStack(spacing: 0) {
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

            // Segment counter badge
            if vm.smsSegmentCount > 0 {
                Text("\(vm.charCount)/\(vm.smsSegmentCount)seg")
                    .font(.brandMono(size: 11))
                    .foregroundStyle(
                        vm.smsSegmentCount > 2 ? Color.bizarreError : Color.bizarreOnSurfaceMuted
                    )
                    .monospacedDigit()
                    .padding(.trailing, BrandSpacing.base)
                    .accessibilityLabel("\(vm.charCount) characters, \(vm.smsSegmentCount) SMS segments")
            }

            // Templates button
            Button {
                showTemplatePicker = true
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 16))
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .padding(.trailing, BrandSpacing.sm)
            .accessibilityLabel("Load message template")
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        .frame(height: 44)
    }

    // MARK: - Input row (To field + text field + send button)

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: BrandSpacing.sm) {
            // "To:" field when no target phone
            if targetPhone == nil {
                toField
            }
            textField
            sendButton
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
    }

    private var toField: some View {
        HStack(spacing: BrandSpacing.xs) {
            Text("To")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("Phone number", text: $toPhone)
                .textFieldStyle(.plain)
                .font(.brandBodyMedium())
                .keyboardType(.phonePad)
                .accessibilityLabel("Recipient phone number")
                .frame(minWidth: 100, maxWidth: 160)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
    }

    private var textField: some View {
        TextField("Reply…", text: $vm.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(minHeight: 44)
            .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
            .focused($composerFocused)
            .lineLimit(1...6)
            .accessibilityLabel("Message body")
            .onSubmit {
                Task { await performSend() }
            }
    }

    private var sendButton: some View {
        Button {
            Task { await performSend() }
        } label: {
            Image(systemName: isSending ? "ellipsis" : "paperplane.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(
                    (!canSend || isSending)
                        ? Color.bizarreOnSurfaceMuted
                        : Color.bizarreOrange,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend || isSending)
        .accessibilityLabel(isSending ? "Sending…" : "Send message")
        .keyboardShortcut(.return, modifiers: .command)
    }

    // MARK: - Error row

    @ViewBuilder
    private var errorRow: some View {
        if let err = sendError {
            Text(err)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreError)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.xs)
                .accessibilityLabel("Send error: \(err)")
        }
    }

    // MARK: - Template picker sheet

    private var templatePickerSheet: some View {
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
        .presentationDetents([.medium, .large])
    }

    // MARK: - Send logic

    private var canSend: Bool {
        vm.isValid && !effectivePhone.isEmpty
    }

    private var effectivePhone: String {
        targetPhone ?? toPhone
    }

    @MainActor
    private func performSend() async {
        let phone = effectivePhone
        guard vm.isValid, !phone.isEmpty, !isSending else { return }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            let body = vm.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            try await onSend(phone, body)
            vm.draft = ""
            composerFocused = false
        } catch {
            sendError = error.localizedDescription
        }
    }
}
