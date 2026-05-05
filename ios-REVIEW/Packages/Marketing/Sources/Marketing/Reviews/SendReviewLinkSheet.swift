import SwiftUI
import DesignSystem

// MARK: - SendReviewLinkViewModel

@Observable
@MainActor
public final class SendReviewLinkViewModel {
    public var selectedPlatform: ReviewPlatform? = nil
    public var isSending = false
    public var errorMessage: String?
    public var didSend = false

    let customerId: String
    let customerName: String
    let service: ReviewSolicitationService

    public init(customerId: String, customerName: String, service: ReviewSolicitationService) {
        self.customerId = customerId
        self.customerName = customerName
        self.service = service
    }

    public func send() async {
        isSending = true
        errorMessage = nil
        do {
            try await service.sendReviewRequest(customerId: customerId, platform: selectedPlatform)
            didSend = true
        } catch ReviewSolicitationError.rateLimited(let days) {
            errorMessage = "Review request already sent. You can send again in \(days) day\(days == 1 ? "" : "s")."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}

// MARK: - SendReviewLinkSheet

/// Called from CustomerDetailView overflow menu. Pre-fills template.
public struct SendReviewLinkSheet: View {
    @State private var vm: SendReviewLinkViewModel
    @Environment(\.dismiss) private var dismiss

    public init(customerId: String, customerName: String, service: ReviewSolicitationService) {
        _vm = State(initialValue: SendReviewLinkViewModel(
            customerId: customerId,
            customerName: customerName,
            service: service
        ))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    platformPicker
                }

                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.bizarreError)
                            .accessibilityLabel("Error: \(err)")
                    }
                }

                Section {
                    sendButton
                }
            }
            .navigationTitle("Send Review Request")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: vm.didSend) { _, sent in
                if sent { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Platform picker

    private var platformPicker: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Platform")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    platformChip(platform: nil, label: "Any")
                    ForEach(ReviewPlatform.allCases, id: \.displayName) { platform in
                        platformChip(platform: platform, label: platform.displayName)
                    }
                }
                .padding(.horizontal, BrandSpacing.xxs)
            }
        }
    }

    private func platformChip(platform: ReviewPlatform?, label: String) -> some View {
        let isSelected = vm.selectedPlatform == platform
        return Button {
            vm.selectedPlatform = platform
        } label: {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .foregroundStyle(isSelected ? Color.bizarreOnOrange : Color.bizarreOnSurface)
        }
        .background(
            isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
            in: Capsule()
        )
        .accessibilityLabel("\(label) platform\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Send button

    private var sendButton: some View {
        Button {
            Task { await vm.send() }
        } label: {
            if vm.isSending {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label("Send Review Request", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .disabled(vm.isSending)
        .accessibilityLabel(vm.isSending ? "Sending review request" : "Send review request to \(vm.customerName)")
    }
}
