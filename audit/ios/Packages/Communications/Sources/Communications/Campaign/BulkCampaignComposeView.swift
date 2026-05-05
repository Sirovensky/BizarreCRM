import SwiftUI
import DesignSystem
import Core

// MARK: - BulkCampaignComposeView

/// §12.12 — Compose a bulk SMS campaign to a customer segment.
///
/// TCPA compliance: previews opted-out count before sending.
/// Sovereignty: sends only to APIClient.baseURL (tenant server).
///
/// Layout:
/// - iPhone: full-screen sheet (`NavigationStack`).
/// - iPad: medium-width popover / sheet with side-by-side panels.
public struct BulkCampaignComposeView: View {

    @Bindable var vm: BulkCampaignViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(vm: BulkCampaignViewModel) { self.vm = vm }

    public var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case .compose:
                    composeForm

                case .previewing:
                    ProgressView("Fetching TCPA-safe preview…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .confirmSend(let preview):
                    confirmView(preview: preview)

                case .sending:
                    ProgressView("Sending campaign…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .done(let ack):
                    doneView(ack: ack)

                case .failed(let msg):
                    errorView(msg)
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New Campaign")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if vm.step == .compose || vm.step == .failed("") {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Compose

    private var composeForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                segmentPicker
                bodyField
                scheduleSection
                previewButton
            }
            .padding(BrandSpacing.base)
        }
    }

    private var segmentPicker: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Audience", systemImage: "person.3")
                .font(.brandBodyLarge().weight(.semibold))
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityHidden(true)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: BrandSpacing.sm
            ) {
                ForEach(BulkCampaignSegment.allCases.filter { $0 != .custom }) { seg in
                    SegmentTile(
                        segment: seg,
                        isSelected: vm.selectedSegment == seg
                    ) {
                        vm.selectedSegment = seg
                    }
                }
            }
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Label("Message", systemImage: "text.bubble")
                    .font(.brandBodyLarge().weight(.semibold))
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text("\(vm.charCount) chars · \(vm.smsSegments) segment\(vm.smsSegments == 1 ? "" : "s")")
                    .font(.brandCaption())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("\(vm.charCount) characters, \(vm.smsSegments) SMS segments")
            }
            TextEditor(text: $vm.body)
                .font(.brandBodyMedium())
                .frame(minHeight: 120, maxHeight: 200)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Campaign message body")
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Toggle(isOn: $vm.isScheduled) {
                Label("Schedule for later", systemImage: "clock")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .tint(.bizarreOrange)

            if vm.isScheduled {
                DatePicker(
                    "Send at",
                    selection: Binding(
                        get: { vm.scheduledDate ?? Date.now.addingTimeInterval(3600) },
                        set: { vm.scheduledDate = $0 }
                    ),
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .padding(.leading, BrandSpacing.sm)
                .accessibilityLabel("Scheduled send time picker")
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private var previewButton: some View {
        Button {
            Task { await vm.preview() }
        } label: {
            Text("Preview campaign")
                .font(.brandBodyLarge().weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
        }
        .buttonStyle(.brandGlass)
        .disabled(!vm.isBodyValid)
        .accessibilityLabel("Preview campaign recipients and compliance check")
    }

    // MARK: - Confirm send

    private func confirmView(preview: BulkCampaignPreview) -> some View {
        VStack(spacing: BrandSpacing.xl) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("\(preview.recipientCount) recipient\(preview.recipientCount == 1 ? "" : "s")")
                    .font(.brandDisplayMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if preview.optedOutCount > 0 {
                    Text("\(preview.optedOutCount) opted-out numbers filtered automatically")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                }
                Text("\(preview.estimatedSegments) SMS segment\(preview.estimatedSegments == 1 ? "" : "s")")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if let warning = preview.tcpaWarning {
                HStack(alignment: .top, spacing: BrandSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityHidden(true)
                    Text(warning)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .multilineTextAlignment(.leading)
                }
                .padding(BrandSpacing.md)
                .background(Color.bizarreWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, BrandSpacing.base)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("TCPA warning: \(warning)")
            }

            HStack(spacing: BrandSpacing.md) {
                Button("Back") {
                    vm.step = .compose
                }
                .font(.brandBodyLarge())
                .buttonStyle(.bordered)
                .tint(.bizarreOnSurface)
                .accessibilityLabel("Back to compose")

                Button("Send to \(preview.recipientCount)") {
                    Task { await vm.send() }
                }
                .font(.brandBodyLarge().weight(.semibold))
                .buttonStyle(.brandGlass)
                .accessibilityLabel("Send campaign to \(preview.recipientCount) recipients")
                .disabled(preview.recipientCount == 0)
            }
            .padding(.horizontal, BrandSpacing.base)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Done

    private func doneView(ack: BulkCampaignAck) -> some View {
        VStack(spacing: BrandSpacing.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text(ack.status == "scheduled" ? "Campaign scheduled" : "Campaign sent")
                    .font(.brandDisplayMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Sent to \(ack.recipientCount) recipient\(ack.recipientCount == 1 ? "" : "s")")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Campaign #\(ack.campaignId)")
                    .font(.brandCaption().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Button("Done") { dismiss() }
                .font(.brandBodyLarge().weight(.semibold))
                .buttonStyle(.brandGlass)
                .padding(.horizontal, BrandSpacing.xl)
                .accessibilityLabel("Done — dismiss campaign screen")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Something went wrong")
                .font(.brandBodyLarge().weight(.semibold))
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            HStack(spacing: BrandSpacing.md) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOnSurface)
                Button("Try again") { vm.step = .compose }
                    .buttonStyle(.brandGlass)
                    .font(.brandBodyLarge())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.base)
    }
}

// MARK: - SegmentTile

private struct SegmentTile: View {
    let segment: BulkCampaignSegment
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: segment.systemIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : .bizarreOrange)
                    .accessibilityHidden(true)
                Text(segment.displayName)
                    .font(.brandCaption())
                    .foregroundStyle(isSelected ? .white : .bizarreOnSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(BrandSpacing.md)
            .background(
                isSelected ? Color.bizarreOrange : Color.bizarreSurface1,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(segment.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
