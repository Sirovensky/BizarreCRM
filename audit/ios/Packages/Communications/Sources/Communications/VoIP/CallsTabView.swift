import SwiftUI
import Networking
import DesignSystem
import Core

// MARK: - §12.10 Calls Tab

/// Calls tab — lists inbound / outbound / missed calls with duration, recording
/// playback, and transcription. Initiates outbound calls via CallKit + server.
///
/// iPhone: TabView tab → NavigationStack, segmented picker at top.
/// iPad:  Same NavigationStack but wider detail; uses Table for the full call list.
public struct CallsTabView: View {

    @State private var vm: CallsTabViewModel
    private let api: APIClient
    @State private var selectedSegment: CallSegment = .all
    @State private var showInitiateSheet: Bool = false

    public init(repo: any CallLogRepository, api: APIClient) {
        _vm = State(wrappedValue: CallsTabViewModel(repo: repo))
        self.api = api
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactBody
            } else {
                regularBody
            }
        }
    }

    // MARK: - iPhone layout

    private var compactBody: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Calls")
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .toolbar { toolbarItems }
            .activeCallBanner(vm: vm)
            .callSheets(vm: vm, api: api)
        }
    }

    // MARK: - iPad layout

    private var regularBody: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Calls")
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .toolbar { toolbarItems }
            .activeCallBanner(vm: vm)
            .callSheets(vm: vm, api: api)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showInitiateSheet = true
            } label: {
                Image(systemName: "phone.badge.plus")
            }
            .accessibilityLabel("Initiate a new call")
            .keyboardShortcut("d", modifiers: [.command])
            .sheet(isPresented: $showInitiateSheet) {
                InitiateCallSheet(vm: vm)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Loading calls…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(err)
        } else if let info = vm.infoMessage, vm.calls.isEmpty {
            infoState(info)
        } else {
            callListWithSegments
        }
    }

    // MARK: - Segment picker + list

    private var callListWithSegments: some View {
        VStack(spacing: 0) {
            segmentPicker
            callList
        }
    }

    private var segmentPicker: some View {
        Picker("Filter", selection: $selectedSegment) {
            ForEach(CallSegment.allCases) { seg in
                Text(seg.label).tag(seg)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
    }

    private var currentCalls: [CallLogEntry] {
        switch selectedSegment {
        case .all:     return vm.calls
        case .inbound: return vm.inboundCalls
        case .outbound: return vm.outboundCalls
        case .missed:  return vm.missedCalls
        }
    }

    @ViewBuilder
    private var callList: some View {
        if currentCalls.isEmpty {
            emptySegmentState
        } else {
            List {
                ForEach(currentCalls) { entry in
                    CallLogRow(entry: entry) {
                        if entry.recordingUrl != nil {
                            vm.openRecordingPlayback(for: entry)
                        }
                    } onTranscript: {
                        if entry.transcriptText != nil {
                            vm.openTranscription(for: entry)
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    #if !os(macOS)
                    .hoverEffect(.highlight)
                    #endif
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Empty / error / info states

    private var emptySegmentState: some View {
        VStack(spacing: BrandSpacing.md) {
            Spacer()
            Image(systemName: "phone.slash")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No \(selectedSegment.label.lowercased()) calls")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load calls")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func infoState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "phone.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Segment

private enum CallSegment: String, CaseIterable, Identifiable {
    case all, inbound, outbound, missed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:      return "All"
        case .inbound:  return "Inbound"
        case .outbound: return "Outbound"
        case .missed:   return "Missed"
        }
    }
}

// MARK: - Call Log Row

private struct CallLogRow: View {
    let entry: CallLogEntry
    let onPlayback: () -> Void
    let onTranscript: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            // Direction icon
            Image(systemName: entry.isInbound
                  ? "phone.arrow.down.left"
                  : "phone.arrow.up.right")
                .font(.title3)
                .foregroundStyle(entry.isInbound ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.customerName ?? entry.phoneNumber)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)

                HStack(spacing: BrandSpacing.xs) {
                    if let ts = entry.startedAt?.prefix(10) {
                        Text(String(ts))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let dur = entry.durationSeconds {
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(Self.formatDuration(dur))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                }
            }

            Spacer(minLength: BrandSpacing.xs)

            // Action buttons: recording + transcript
            HStack(spacing: BrandSpacing.sm) {
                if entry.recordingUrl != nil {
                    Button { onPlayback() } label: {
                        Image(systemName: "play.circle")
                            .font(.title3)
                            .foregroundStyle(.bizarreOrange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play recording")
                }
                if entry.transcriptText != nil {
                    Button { onTranscript() } label: {
                        Image(systemName: "text.bubble")
                            .font(.title3)
                            .foregroundStyle(.bizarreOrange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View transcript")
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var parts: [String] = []
        parts.append(entry.isInbound ? "Inbound call" : "Outbound call")
        parts.append(entry.customerName ?? entry.phoneNumber)
        if let ts = entry.startedAt?.prefix(10) { parts.append(String(ts)) }
        if let dur = entry.durationSeconds { parts.append("Duration \(dur / 60) minutes \(dur % 60) seconds") }
        if entry.recordingUrl != nil { parts.append("Recording available") }
        if entry.transcriptText != nil { parts.append("Transcript available") }
        return parts.joined(separator: ". ")
    }

    static func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Active Call Banner

private struct ActiveCallBannerModifier: ViewModifier {
    @Bindable var vm: CallsTabViewModel

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if vm.activeOutboundCallId != nil {
                activeCallBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: vm.activeOutboundCallId)
            }
        }
    }

    private var activeCallBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "phone.fill")
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityHidden(true)
            Text("Call in progress…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if vm.isHangingUp {
                ProgressView()
            } else {
                Button {
                    Task { await vm.hangup() }
                } label: {
                    Label("Hang Up", systemImage: "phone.down.fill")
                        .font(.brandLabelMedium())
                        .foregroundStyle(.white)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xs)
                        .background(Color.bizarreError, in: Capsule())
                }
                .accessibilityLabel("Hang up call")
            }
        }
        .padding(BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, BrandSpacing.md)
        .padding(.top, BrandSpacing.sm)
    }
}

private extension View {
    func activeCallBanner(vm: CallsTabViewModel) -> some View {
        modifier(ActiveCallBannerModifier(vm: vm))
    }
}

// MARK: - Sheet wiring

private struct CallSheetsModifier: ViewModifier {
    @Bindable var vm: CallsTabViewModel
    let api: APIClient

    func body(content: Content) -> some View {
        content
            .sheet(item: $vm.selectedForPlayback) { entry in
                CallRecordingPlayerSheet(entry: entry, api: api)
            }
            .sheet(item: $vm.selectedForTranscript) { entry in
                CallTranscriptSheet(entry: entry)
            }
    }
}

private extension View {
    func callSheets(vm: CallsTabViewModel, api: APIClient) -> some View {
        modifier(CallSheetsModifier(vm: vm, api: api))
    }
}

// MARK: - Initiate Call Sheet

/// Simple sheet to enter a phone number and initiate a call.
struct InitiateCallSheet: View {
    @Bindable var vm: CallsTabViewModel
    @State private var phoneNumber: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Phone number") {
                    TextField("+1 (555) 000-0000", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .accessibilityLabel("Phone number to call")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
            .navigationTitle("Make a Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Call") {
                        let number = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !number.isEmpty else { return }
                        Task {
                            await vm.initiateCall(to: number)
                            dismiss()
                        }
                    }
                    .disabled(phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Start call to entered phone number")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
