import SwiftUI
import Core
import DesignSystem
import Networking

public struct SmsThreadView: View {
    @State private var vm: SmsThreadViewModel
    @FocusState private var composerFocused: Bool

    public init(repo: SmsThreadRepository, phoneNumber: String) {
        _vm = State(wrappedValue: SmsThreadViewModel(repo: repo, phoneNumber: phoneNumber))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                messagesList
                composer
            }
        }
        .navigationTitle(threadTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var threadTitle: String {
        if let name = vm.thread?.customer?.displayName, !name.isEmpty, name != "Unknown" {
            return name
        }
        return PhoneFormatter.format(vm.phoneNumber)
    }

    @ViewBuilder
    private var messagesList: some View {
        if vm.isLoading, vm.thread == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.thread == nil {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                Text("Couldn't load thread")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let thread = vm.thread {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: BrandSpacing.sm) {
                        if thread.messages.isEmpty {
                            VStack(spacing: BrandSpacing.md) {
                                Image(systemName: "message")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                Text("No messages yet").font(.brandTitleMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, BrandSpacing.xxl)
                        } else {
                            ForEach(thread.messages) { message in
                                MessageBubble(message: message).id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.md)
                }
                .onChange(of: thread.messages.count) { _, _ in
                    if let lastId = thread.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let lastId = thread.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.bizarreOutline.opacity(0.5))
            HStack(alignment: .bottom, spacing: BrandSpacing.sm) {
                TextField("Message", text: $vm.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .frame(minHeight: 44)
                    .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                    .focused($composerFocused)
                    .lineLimit(1...5)

                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: vm.isSending ? "ellipsis" : "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(
                            (vm.draft.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.bizarreOnSurfaceMuted
                                : Color.bizarreOrange),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(vm.isSending || vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)

            if let err = vm.errorMessage, vm.thread != nil {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.xs)
            }
        }
        .background(Color.bizarreSurface1.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Bubble

private struct MessageBubble: View {
    let message: SmsMessage

    var body: some View {
        HStack {
            if message.isOutbound { Spacer(minLength: 40) }
            VStack(alignment: message.isOutbound ? .trailing : .leading, spacing: 2) {
                Text(message.message ?? "")
                    .font(.brandBodyMedium())
                    .foregroundStyle(message.isOutbound ? .bizarreOnOrange : .bizarreOnSurface)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(
                        message.isOutbound ? Color.bizarreOrangeContainer : Color.bizarreSurface2,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                HStack(spacing: BrandSpacing.xs) {
                    if let ts = message.createdAt {
                        Text(String(ts.prefix(16)).replacingOccurrences(of: "T", with: " "))
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if message.isOutbound, let label = message.statusLabel {
                        Text(label)
                            .font(.brandMono(size: 11))
                            .foregroundStyle(message.failed ? .bizarreError : .bizarreOnSurfaceMuted)
                    }
                }
            }
            if !message.isOutbound { Spacer(minLength: 40) }
        }
    }
}
