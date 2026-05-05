import SwiftUI
import Core
import DesignSystem

// MARK: - GroupSendConfirmAlert

/// Alert-style confirmation for group send: shows recipient count + estimated cost.
/// Uses `.alert` modifier for Liquid Glass consistent system presentation.
public struct GroupSendConfirmAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let vm: GroupSendViewModel
    let onConfirm: () -> Void

    public func body(content: Content) -> some View {
        content
            .alert("Send to \(vm.recipientCountLabel)?", isPresented: $isPresented) {
                Button("Send to all", role: .none) {
                    onConfirm()
                }
                .accessibilityLabel("Confirm send to \(vm.recipientCountLabel)")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will send \(vm.estimatedCostLabel) to \(vm.recipientCountLabel). Each recipient gets a separate thread.")
            }
    }
}

public extension View {
    func groupSendConfirmAlert(
        isPresented: Binding<Bool>,
        vm: GroupSendViewModel,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(GroupSendConfirmAlertModifier(isPresented: isPresented, vm: vm, onConfirm: onConfirm))
    }
}

// MARK: - GroupMessageComposer

/// Compose-once-send-to-N view.
/// iPhone: stacked VStack, full-screen navigation.
/// iPad: side-by-side split (recipients | composer).
public struct GroupMessageComposer: View {
    @State private var vm: GroupSendViewModel
    @State private var showRecipientPicker: Bool = false
    @State private var showConfirmAlert: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(vm: GroupSendViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    recipientBar
                    Divider()
                    bodyEditor
                    progressBar
                }
            }
            .navigationTitle("Group Message")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    sendButton
                }
            }
            .sheet(isPresented: $showRecipientPicker) {
                GroupRecipientPickerView(recipients: $vm.recipients)
            }
            .groupSendConfirmAlert(isPresented: $showConfirmAlert, vm: vm) {
                Task { await vm.send() }
            }
        }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        HStack(spacing: 0) {
            // Left: recipients
            VStack(alignment: .leading, spacing: 0) {
                GroupRecipientPickerView(recipients: $vm.recipients)
            }
            .frame(width: 320)

            Divider()

            // Right: composer
            VStack(spacing: 0) {
                bodyEditor
                progressBar
                HStack {
                    Spacer()
                    sendButton
                        .padding(BrandSpacing.base)
                }
            }
        }
        .groupSendConfirmAlert(isPresented: $showConfirmAlert, vm: vm) {
            Task { await vm.send() }
        }
    }

    // MARK: - Sub-views

    private var recipientBar: some View {
        Button {
            showRecipientPicker = true
        } label: {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(vm.recipients.isEmpty ? "Add recipients" : vm.recipientCountLabel)
                    .font(.brandBodyMedium())
                    .foregroundStyle(vm.recipients.isEmpty ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.base)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreSurface1)
        .accessibilityLabel(vm.recipients.isEmpty ? "Add recipients, none selected" : "\(vm.recipientCountLabel) selected, tap to change")
    }

    private var bodyEditor: some View {
        TextEditor(text: $vm.body)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
            .padding(BrandSpacing.base)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if vm.body.isEmpty {
                    Text("Write your message…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.top, BrandSpacing.base + 8)
                        .padding(.leading, BrandSpacing.base + 4)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Message body")
    }

    @ViewBuilder
    private var progressBar: some View {
        if vm.isSending {
            ProgressView(value: vm.progress)
                .tint(.bizarreOrange)
                .padding(.horizontal, BrandSpacing.base)
        }
        if let err = vm.errorMessage {
            Text(err)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreError)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.xs)
        }
        if vm.didSend, let ack = vm.lastAck {
            Text("Queued \(ack.queued) message\(ack.queued == 1 ? "" : "s")\(ack.failed > 0 ? ", \(ack.failed) failed" : "")")
                .font(.brandBodyMedium())
                .foregroundStyle(ack.failed > 0 ? .bizarreError : .bizarreOrange)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.xs)
        }
    }

    private var sendButton: some View {
        Button {
            showConfirmAlert = true
        } label: {
            Label("Send", systemImage: "paperplane.fill")
                .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(!vm.canSend || vm.isSending)
    }
}
