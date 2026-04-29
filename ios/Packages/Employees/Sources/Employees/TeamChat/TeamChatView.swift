import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - TeamChatView
//
// §14.5 Team chat — channel-less surface (single "general" channel under the
// hood). Per platform:
//   • iPhone: full-bleed message list with a sticky composer.
//   • iPad: split with a Pinned-messages sidebar on the leading edge.

public struct TeamChatView: View {
    @State private var vm: TeamChatViewModel
    @State private var showPinnedSheet = false
    @State private var attachmentSheetMode: AttachmentSheetMode?
    private let api: APIClient
    private let authToken: String?

    public init(api: APIClient, authToken: String? = nil) {
        self.api = api
        self.authToken = authToken
        let repo = TeamChatRepositoryImpl(api: api)
        _vm = State(wrappedValue: TeamChatViewModel(repo: repo))
    }

    public var body: some View {
        Group {
            #if canImport(UIKit)
            if Platform.isIPad {
                ipadLayout
            } else {
                iphoneLayout
            }
            #else
            iphoneLayout
            #endif
        }
        .navigationTitle("Team Chat")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPinnedSheet = true
                } label: {
                    Label("Pinned", systemImage: "pin.fill")
                }
                .accessibilityLabel("View pinned messages")
            }
        }
        .sheet(isPresented: $showPinnedSheet) {
            PinnedMessagesSheet(messages: vm.pinnedMessages,
                                onUnpin: { vm.togglePin($0) })
        }
        .task {
            await vm.start()
        }
        .onDisappear { vm.stop() }
    }

    // MARK: iPhone

    @ViewBuilder
    private var iphoneLayout: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
    }

    // MARK: iPad — sidebar with pinned messages

    @ViewBuilder
    private var ipadLayout: some View {
        HStack(spacing: 0) {
            pinnedSidebar
                .frame(width: 280)
                .background(Color.bizarreSurface1)
            Divider()
            VStack(spacing: 0) {
                messageList
                composer
            }
        }
    }

    @ViewBuilder
    private var pinnedSidebar: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "pin.fill").foregroundStyle(Color.bizarrePrimary)
                Text("Pinned").font(.headline).foregroundStyle(Color.bizarreText)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.base)
            if vm.pinnedMessages.isEmpty {
                Text("No pinned messages.")
                    .font(.footnote)
                    .foregroundStyle(Color.bizarreTextSecondary)
                    .padding(.horizontal, BrandSpacing.base)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        ForEach(vm.pinnedMessages) { msg in
                            PinnedMessageRow(message: msg, onUnpin: { vm.togglePin(msg) })
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                }
            }
            Spacer()
        }
    }

    // MARK: Message list

    @ViewBuilder
    private var messageList: some View {
        if vm.isLoading && vm.messages.isEmpty {
            ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.messages.isEmpty {
            ContentUnavailableView(
                "Couldn't Load Chat",
                systemImage: "exclamationmark.triangle",
                description: Text(err)
            )
        } else if vm.messages.isEmpty {
            ContentUnavailableView(
                "No Messages Yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Start the conversation. Use @username to mention a teammate.")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: BrandSpacing.sm) {
                        ForEach(vm.messages) { msg in
                            TeamChatMessageRow(
                                message: msg,
                                isPinned: vm.isPinned(msg),
                                onTogglePin: { vm.togglePin(msg) },
                                onDelete: { Task { await vm.delete(msg) } }
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
                }
                .onChange(of: vm.messages.last?.id) { _, newId in
                    guard let newId else { return }
                    withAnimation { proxy.scrollTo(newId, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Composer

    @ViewBuilder
    private var composer: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            if let attachment = vm.pendingAttachment {
                AttachmentChip(attachment: attachment) {
                    vm.pendingAttachment = nil
                }
            }
            if !vm.draftMentions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.xs) {
                        ForEach(vm.draftMentions, id: \.self) { name in
                            Text("@\(name)")
                                .font(.caption.bold())
                                .padding(.horizontal, BrandSpacing.sm)
                                .padding(.vertical, BrandSpacing.xxs)
                                .background(Color.bizarrePrimary.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.bizarrePrimary)
                        }
                    }
                }
            }
            HStack(spacing: BrandSpacing.sm) {
                Menu {
                    Button {
                        attachmentSheetMode = .photo
                    } label: {
                        Label("Photo", systemImage: "photo")
                    }
                    Button {
                        attachmentSheetMode = .file
                    } label: {
                        Label("File", systemImage: "paperclip")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.bizarrePrimary)
                }
                .accessibilityLabel("Attach photo or file")
                TextField("Message…", text: $vm.draftBody, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(vm.isSending || (vm.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && vm.pendingAttachment == nil))
                .accessibilityLabel("Send message")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1)
        #if canImport(PhotosUI)
        .sheet(item: $attachmentSheetMode) { mode in
            switch mode {
            case .photo:
                TeamChatPhotoPicker(api: api, authToken: authToken) { attachment in
                    vm.pendingAttachment = attachment
                    attachmentSheetMode = nil
                }
            case .file:
                TeamChatFilePicker(api: api, authToken: authToken) { attachment in
                    vm.pendingAttachment = attachment
                    attachmentSheetMode = nil
                }
            }
        }
        #endif
    }
}

private enum AttachmentSheetMode: String, Identifiable {
    case photo, file
    var id: String { rawValue }
}

// MARK: - Row

struct TeamChatMessageRow: View {
    let message: TeamMessageRow
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let parsed = TeamChatAttachmentEncoder.decode(body: message.body)
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.bizarreText)
                Text(message.createdAt)
                    .font(.caption2)
                    .foregroundStyle(Color.bizarreTextSecondary)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.bizarrePrimary)
                        .accessibilityLabel("Pinned")
                }
                Spacer()
            }
            if !parsed.text.isEmpty {
                Text(highlighted(parsed.text))
                    .font(.body)
                    .foregroundStyle(Color.bizarreText)
                    .textSelection(.enabled)
            }
            ForEach(parsed.attachments, id: \.self) { att in
                AttachmentPreviewRow(attachment: att)
            }
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Bolds `@username` tokens to make mentions stand out.
    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        let pattern = #"@[a-zA-Z0-9_.\-]{2,32}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return attr }
        let ns = text as NSString
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, let range = Range(m.range, in: text),
                  let attrRange = attr.range(of: String(text[range])) else { return }
            attr[attrRange].font = .body.weight(.semibold)
            attr[attrRange].foregroundColor = .bizarrePrimary
        }
        return attr
    }
}

// MARK: - Attachment chip + preview

struct AttachmentChip: View {
    let attachment: TeamChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: attachment.isImage ? "photo" : "paperclip")
                .foregroundStyle(Color.bizarrePrimary)
            Text(attachment.fileName)
                .font(.footnote)
                .lineLimit(1)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.bizarreTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface2, in: Capsule())
    }
}

struct AttachmentPreviewRow: View {
    let attachment: TeamChatAttachment

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: attachment.isImage ? "photo.fill" : "doc.fill")
                .foregroundStyle(Color.bizarrePrimary)
            Text(attachment.fileName)
                .font(.footnote)
                .foregroundStyle(Color.bizarreText)
                .lineLimit(1)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurfaceBase, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Attachment: \(attachment.fileName)")
    }
}

// MARK: - PinnedMessagesSheet (iPhone)

struct PinnedMessagesSheet: View {
    let messages: [TeamMessageRow]
    let onUnpin: (TeamMessageRow) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if messages.isEmpty {
                    ContentUnavailableView(
                        "No Pinned Messages",
                        systemImage: "pin.slash",
                        description: Text("Pin a message to keep it handy.")
                    )
                } else {
                    List(messages) { msg in
                        PinnedMessageRow(message: msg, onUnpin: { onUnpin(msg) })
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Pinned")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct PinnedMessageRow: View {
    let message: TeamMessageRow
    let onUnpin: () -> Void

    var body: some View {
        let parsed = TeamChatAttachmentEncoder.decode(body: message.body)
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(message.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.bizarreTextSecondary)
            if !parsed.text.isEmpty {
                Text(parsed.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.bizarreText)
                    .lineLimit(3)
            }
            if !parsed.attachments.isEmpty {
                Text("\(parsed.attachments.count) attachment\(parsed.attachments.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(Color.bizarreTextSecondary)
            }
        }
        .swipeActions {
            Button {
                onUnpin()
            } label: {
                Label("Unpin", systemImage: "pin.slash")
            }
            .tint(Color.bizarrePrimary)
        }
    }
}
