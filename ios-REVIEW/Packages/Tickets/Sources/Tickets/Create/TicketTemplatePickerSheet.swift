#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.10 — Device template picker sheet.
//
// Presents a searchable list of `DeviceTemplate` records fetched from
// `GET /api/v1/device-templates`.  When the user selects a template the
// `onPick` closure is called with the chosen template so the caller
// (TicketCreateFlowView / bench workflow) can pre-fill device family,
// model, services and the diagnostic checklist.
//
// iPhone: bottom sheet (.large detent).
// iPad: same sheet — NavigationStack provides its own nav bar.

// MARK: - ViewModel

@MainActor
@Observable
final class TicketTemplatePickerViewModel {

    // MARK: - State

    private(set) var templates: [DeviceTemplate] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    var searchText: String = ""

    /// Templates filtered by family and/or search text.
    var filtered: [DeviceTemplate] {
        let base = selectedFamily == nil
            ? templates
            : templates.filter { $0.family?.lowercased() == selectedFamily?.lowercased() }
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        let lower = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(lower) ||
            ($0.model?.lowercased().contains(lower) == true) ||
            ($0.family?.lowercased().contains(lower) == true)
        }
    }

    /// All unique family / category values for the filter chip row.
    var families: [String] {
        Array(Set(templates.compactMap { $0.family })).sorted()
    }

    var selectedFamily: String?

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await api.listDeviceTemplates()
        } catch {
            AppLog.ui.error(
                "TicketTemplatePicker load failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

/// Bottom sheet that lets the user browse and pick a device repair template.
public struct TicketTemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketTemplatePickerViewModel
    private let onPick: (DeviceTemplate) -> Void

    /// - Parameters:
    ///   - api: Live `APIClient` injected by the parent.
    ///   - onPick: Called with the selected template; sheet dismisses automatically.
    public init(api: APIClient, onPick: @escaping (DeviceTemplate) -> Void) {
        self.onPick = onPick
        _vm = State(wrappedValue: TicketTemplatePickerViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Device Templates")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search templates…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await vm.load() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading device templates")
        } else if let err = vm.errorMessage {
            errorView(err)
        } else if vm.templates.isEmpty {
            emptyView
        } else {
            templateList
        }
    }

    private var templateList: some View {
        VStack(spacing: 0) {
            // Family filter chip row
            if !vm.families.isEmpty {
                familyChipRow
                    .padding(.vertical, BrandSpacing.sm)
                Divider().overlay(Color.bizarreOutline.opacity(0.2))
            }

            List {
                if vm.filtered.isEmpty {
                    Text("No templates match your search.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(vm.filtered) { template in
                        templateRow(template)
                            .listRowBackground(Color.bizarreSurface1)
                            .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var familyChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                templateFamilyChip(label: "All", selected: vm.selectedFamily == nil) {
                    vm.selectedFamily = nil
                }
                ForEach(vm.families, id: \.self) { family in
                    templateFamilyChip(label: family, selected: vm.selectedFamily == family) {
                        vm.selectedFamily = vm.selectedFamily == family ? nil : family
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
        .scrollClipDisabled()
    }

    private func templateFamilyChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(selected ? Color.black : Color.bizarreOnSurface)
                .background(selected ? Color.bizarreOrange : Color.bizarreSurface1, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(selected ? 0 : 0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func templateRow(_ template: DeviceTemplate) -> some View {
        Button {
            onPick(template)
            dismiss()
        } label: {
            HStack(spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(template.name)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)

                    if let model = template.model, !model.isEmpty {
                        Text(model)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }

                    if let minutes = template.estimatedMinutes, minutes > 0 {
                        Label("\(minutes) min estimated", systemImage: "clock")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()

                if let cents = template.defaultPriceCents, cents > 0 {
                    Text(formatCents(cents))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(accessibilityLabel(for: template))
        .accessibilityHint("Select to pre-fill device and repair details")
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No device templates")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Add templates in Settings → Device Templates to pre-fill common repairs.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load templates")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.lg)
    }

    // MARK: - Helpers

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    private func accessibilityLabel(for template: DeviceTemplate) -> String {
        var parts = [template.name]
        if let model = template.model { parts.append(model) }
        if let minutes = template.estimatedMinutes, minutes > 0 {
            parts.append("\(minutes) minutes estimated")
        }
        if let cents = template.defaultPriceCents, cents > 0 {
            parts.append(formatCents(cents))
        }
        return parts.joined(separator: ", ")
    }
}

#endif
