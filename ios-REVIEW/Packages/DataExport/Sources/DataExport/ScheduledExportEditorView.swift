import SwiftUI
import DesignSystem
import Core

// MARK: - ScheduledExportEditorView

/// Create or edit a scheduled export configuration.
/// iPhone: presented as a sheet with NavigationStack.
/// iPad: shown in NavigationSplitView detail or side panel.
public struct ScheduledExportEditorView: View {

    @State private var viewModel: DataExportViewModel
    @State private var cadence: ExportCadence
    @State private var destination: ExportDestination
    @State private var isSaving: Bool = false

    private let onDismiss: () -> Void

    public init(
        viewModel: DataExportViewModel,
        schedule: ScheduledExport? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self._viewModel = State(wrappedValue: viewModel)
        self._cadence = State(wrappedValue: schedule?.cadence ?? .daily)
        self._destination = State(wrappedValue: schedule?.destination ?? .icloud)
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            editorForm
                .navigationTitle("New Schedule")
                .exportInlineTitleMode()
                .exportToolbarBackground()
                .toolbar { toolbarContent }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        editorForm
            .navigationTitle("New Schedule")
            .exportToolbarBackground()
            .toolbar { toolbarContent }
    }

    // MARK: - Form

    private var editorForm: some View {
        Form {
            Section("Cadence") {
                Picker("Frequency", selection: $cadence) {
                    ForEach(ExportCadence.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Export frequency")
            }

            Section {
                Picker("Destination", selection: $destination) {
                    ForEach(ExportDestination.allCases, id: \.self) { d in
                        HStack {
                            Label(d.displayName, systemImage: d.systemImage)
                            if !d.isImplemented {
                                Spacer()
                                Text("Coming soon")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(d)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("Export destination")
            } header: {
                Text("Destination")
            } footer: {
                if !destination.isImplemented {
                    // TODO §49.4: implement S3 and Dropbox OAuth flows
                    Label(
                        "\(destination.displayName) integration is not yet configured. Only iCloud Drive is available.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else {
                    Text("Files are saved to your iCloud Drive / BizarreCRM folder.")
                        .font(.caption)
                }
            }
        }
        .disabled(isSaving)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { onDismiss() }
                .accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
                    .accessibilityLabel("Saving…")
            } else {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!destination.isImplemented)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Save scheduled export")
                .accessibilityHint(destination.isImplemented ? "" : "Select iCloud Drive to enable saving")
            }
        }
    }

    // MARK: - Actions

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await viewModel.saveSchedule(cadence: cadence, destination: destination)
        if viewModel.errorMessage == nil { onDismiss() }
    }
}
