import SwiftUI
import Core
import DesignSystem

// MARK: - NotificationMatrixView
//
// §70 Granular Per-Event Notification Matrix View
//
// iPad (regular width):  NavigationSplitView — categories left pane, event grid right pane.
// iPhone (compact width): Full-screen vertical scroll with category section headers.
//
// Channels shown: Push / Email / SMS (In-App always on, not user-toggled).
// Liquid Glass chrome on toolbars and saving-indicator pill.

public struct NotificationMatrixView: View {

    @State private var vm: NotificationMatrixViewModel
    @State private var selectedCategory: MatrixEventCategory = .tickets
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(repository: any NotifPrefsRepository) {
        _vm = State(wrappedValue: NotificationMatrixViewModel(repository: repository))
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .task { await vm.load() }
        .overlay(alignment: .top) { savingPill }
        // SMS cost warning
        .alert("SMS Volume Warning", isPresented: $vm.showSMSCostWarning) {
            Button("Enable SMS", role: .destructive) {
                Task { await vm.confirmSMSToggle() }
            }
            Button("Cancel", role: .cancel) { vm.cancelSMSToggle() }
        } message: {
            Text("This event fires frequently. Enabling SMS may generate 50+ texts per day and charges may apply.")
        }
        // Quiet hours sheet
        .sheet(item: $vm.editingQuietHoursEvent) { event in
            quietHoursSheet(for: event)
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            categorySidebar
        } detail: {
            eventGrid(for: selectedCategory)
                .navigationTitle(selectedCategory.rawValue)
                .toolbar { matrixToolbar }
        }
    }

    private var categorySidebar: some View {
        List {
            ForEach(MatrixEventCategory.allCases, id: \.self) { category in
                Button { selectedCategory = category } label: {
                    HStack {
                        Label(category.rawValue, systemImage: category.symbolName)
                            .font(.brandBodyLarge())
                        Spacer()
                        if selectedCategory == category {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(category.rawValue)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationTitle("Categories")
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.preferences.isEmpty {
                    loadingView
                } else if let err = vm.errorMessage, vm.preferences.isEmpty {
                    errorView(err)
                } else {
                    iPhoneScrollContent
                }
            }
            .navigationTitle("Notification Matrix")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { matrixToolbar }
        }
    }

    private var iPhoneScrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(MatrixEventCategory.allCases) { category in
                    let rows = vm.rows(for: category)
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { row in
                                eventRowCell(row: row)
                                    .padding(.horizontal, BrandSpacing.md)
                                    .padding(.vertical, 2)
                            }
                        } header: {
                            categoryHeader(category)
                        }
                    }
                }
                resetRow
                    .padding(BrandSpacing.md)
            }
        }
        .background(Color.bizarreSurfaceBase)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var matrixToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.resetAllToDefaults() }
            } label: {
                Text("Reset All")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Reset all notification preferences to defaults")
            .accessibilityIdentifier("matrix.resetAll")
        }
    }

    // MARK: - Event grid (iPad detail)

    @ViewBuilder
    private func eventGrid(for category: MatrixEventCategory) -> some View {
        let rows = vm.rows(for: category)
        if vm.isLoading && rows.isEmpty {
            loadingView
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    channelHeaderRow
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.bottom, BrandSpacing.xs)

                    ForEach(rows) { row in
                        eventRowCell(row: row)
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, 2)
                    }
                    resetRow.padding(BrandSpacing.md)
                }
                .padding(.top, BrandSpacing.sm)
            }
            .background(Color.bizarreSurfaceBase)
        }
    }

    // MARK: - Channel header row

    private var channelHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Event")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            ForEach(MatrixChannel.allCases) { channel in
                VStack(spacing: 2) {
                    Image(systemName: channel.symbolName)
                        .font(.caption)
                    Text(channel.displayLabel)
                        .font(.brandLabelSmall())
                }
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 60, alignment: .center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Column: \(channel.displayLabel)")
            }

            // Extra width for the quiet-hours clock button
            Spacer().frame(width: 44)
        }
        .padding(.vertical, BrandSpacing.xs)
        .padding(.horizontal, BrandSpacing.sm)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Category header (iPhone)

    private func categoryHeader(_ category: MatrixEventCategory) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: category.symbolName)
                .font(.caption)
                .foregroundStyle(.bizarreOrange)
            Text(category.rawValue)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurfaceBase)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Event row cell

    @ViewBuilder
    private func eventRowCell(row: MatrixRow) -> some View {
        HStack(spacing: 0) {
            // Event label + critical badge
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(row.event.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                if row.event.isCritical {
                    Text("Critical")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreWarning)
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, 1)
                        .background(Color.bizarreWarning.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(row.event.displayName)

            // Channel toggles
            ForEach(MatrixChannel.allCases) { channel in
                channelToggleButton(row: row, channel: channel)
                    .frame(width: 60, alignment: .center)
            }

            // Quiet-hours clock button
            quietHoursButton(for: row)
                .frame(width: 44, alignment: .center)
        }
        .padding(.vertical, BrandSpacing.sm)
        .padding(.horizontal, BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notification row: \(row.event.displayName)")
    }

    // MARK: - Channel toggle button

    @ViewBuilder
    private func channelToggleButton(row: MatrixRow, channel: MatrixChannel) -> some View {
        let isOn = row.isEnabled(channel)
        // §70.1 — show "(default)" label greyed when value has not been changed from shipped default
        let atDefault = row.isAtDefault(for: channel)
        Button {
            Task { await vm.toggle(event: row.event, channel: channel) }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        atDefault
                            ? (isOn ? Color.bizarreOrange.opacity(0.5) : Color.bizarreOnSurfaceMuted.opacity(0.5))
                            : (isOn ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    )
                    .font(.title3)
                if atDefault {
                    Text("default")
                        .font(.system(size: 8))
                        .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.6))
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(channel.displayLabel) for \(row.event.displayName): \(isOn ? "on" : "off")\(atDefault ? " (default)" : "")")
        .accessibilityHint("Double-tap to \(isOn ? "disable" : "enable")")
        .accessibilityIdentifier("matrix.\(row.event.rawValue).\(channel.rawValue)")
    }

    // MARK: - Quiet-hours button

    @ViewBuilder
    private func quietHoursButton(for row: MatrixRow) -> some View {
        Button {
            vm.editingQuietHoursEvent = row.event
        } label: {
            Image(systemName: row.quietHours != nil ? "clock.fill" : "clock")
                .foregroundStyle(row.quietHours != nil ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .font(.body)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.quietHours != nil
            ? "Quiet hours set for \(row.event.displayName)"
            : "Set quiet hours for \(row.event.displayName)")
        .accessibilityIdentifier("matrix.quietHours.\(row.event.rawValue)")
    }

    // MARK: - Reset row

    private var resetRow: some View {
        Button("Reset all to defaults") {
            Task { await vm.resetAllToDefaults() }
        }
        .font(.brandLabelLarge())
        .foregroundStyle(.bizarreOrange)
        .accessibilityLabel("Reset all notification preferences to defaults")
        .accessibilityIdentifier("matrix.resetAllBottom")
    }

    // MARK: - Saving pill (Liquid Glass)

    @ViewBuilder
    private var savingPill: some View {
        if vm.isSaving {
            HStack(spacing: BrandSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Saving…")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .padding(BrandSpacing.md)
            .brandGlass(.regular, in: Capsule())
            .padding(.top, BrandSpacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Loading / error views

    private var loadingView: some View {
        ProgressView("Loading preferences…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading notification matrix")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load preferences")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Quiet hours sheet

    private func quietHoursSheet(for event: NotificationEvent) -> some View {
        let currentQH = vm.matrix.rows.first(where: { $0.event == event })?.quietHours
        return NavigationStack {
            MatrixQuietHoursEditor(
                initialQuietHours: currentQH,
                onSave: { qh in
                    Task { await vm.saveQuietHours(qh, for: event) }
                }
            )
            .navigationTitle("Quiet Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.editingQuietHoursEvent = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
