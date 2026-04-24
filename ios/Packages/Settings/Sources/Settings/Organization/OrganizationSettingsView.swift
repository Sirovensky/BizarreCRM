import SwiftUI
import Core
import DesignSystem

// MARK: - §19.5 OrganizationSettingsView

/// Settings form for organisation-level data (name, address, timezone, etc.).
/// Admin-gated: when `canEdit` is `false` all fields are read-only and the
/// Save button is hidden.
public struct OrganizationSettingsView: View {

    @State private var vm: OrganizationSettingsViewModel

    /// `true` when the authenticated user has admin / owner permissions.
    private let canEdit: Bool

    // MARK: - Init

    public init(
        repository: any OrganizationSettingsRepository,
        canEdit: Bool
    ) {
        _vm = State(initialValue: OrganizationSettingsViewModel(repository: repository))
        self.canEdit = canEdit
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                padLayout
            }
        }
        .navigationTitle("Organisation")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await vm.load() }
        .overlay { loadingOverlay }
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
        }
    }

    // MARK: - Layouts

    private var phoneLayout: some View {
        Form {
            identitySection
            contactSection
            localisationSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if canEdit { saveFooter }
        }
    }

    private var padLayout: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .top,
                spacing: BrandSpacing.lg
            ) {
                identityCard
                contactCard
                localisationCard
            }
            .padding(BrandSpacing.lg)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Sections (Phone)

    private var identitySection: some View {
        Section {
            brandField("Trading Name", text: nameBinding)
            brandField("Legal Name", text: legalNameBinding)
            brandField("Tax / EIN", text: taxIdBinding)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .keyboardType(.asciiCapable)
                #endif
            brandField("Logo URL", text: logoUrlBinding)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
        } header: {
            Text("Identity")
        }
    }

    private var contactSection: some View {
        Section {
            brandField("Address", text: addressBinding)
            brandField("Phone", text: phoneBinding)
                #if canImport(UIKit)
                .keyboardType(.phonePad)
                #endif
            brandField("Email", text: emailBinding)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
        } header: {
            Text("Contact")
        }
    }

    private var localisationSection: some View {
        Section {
            timezonePicker
            currencyPicker
            localePicker
        } header: {
            Text("Localisation")
        }
    }

    // MARK: - Cards (iPad)

    private var identityCard: some View {
        GroupBox("Identity") {
            VStack(spacing: BrandSpacing.sm) {
                padField("Trading Name", text: nameBinding)
                padField("Legal Name", text: legalNameBinding)
                padField("Tax / EIN", text: taxIdBinding)
                padField("Logo URL", text: logoUrlBinding)
            }
        }
        .groupBoxStyle(.organization)
    }

    private var contactCard: some View {
        GroupBox("Contact") {
            VStack(spacing: BrandSpacing.sm) {
                padField("Address", text: addressBinding)
                padField("Phone", text: phoneBinding)
                padField("Email", text: emailBinding)
            }
        }
        .groupBoxStyle(.organization)
    }

    private var localisationCard: some View {
        GroupBox("Localisation") {
            VStack(spacing: BrandSpacing.sm) {
                timezonePicker
                    .hoverEffect(.highlight)
                currencyPicker
                    .hoverEffect(.highlight)
                localePicker
                    .hoverEffect(.highlight)
            }
        }
        .groupBoxStyle(.organization)
    }

    // MARK: - Pickers

    private var timezonePicker: some View {
        Picker("Timezone", selection: timezoneBinding) {
            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
        }
        .disabled(!canEdit)
        .accessibilityLabel("Timezone")
    }

    private var currencyPicker: some View {
        Picker("Currency", selection: currencyBinding) {
            ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { Text($0).tag($0) }
        }
        .disabled(!canEdit)
        .accessibilityLabel("Currency")
    }

    private var localePicker: some View {
        Picker("Locale", selection: localeBinding) {
            ForEach(Locale.availableIdentifiers.sorted(), id: \.self) { Text($0).tag($0) }
        }
        .disabled(!canEdit)
        .accessibilityLabel("Locale")
    }

    // MARK: - Save UI

    private var saveButton: some View {
        Button("Save") { Task { await vm.save() } }
            .disabled(vm.isSaving)
            .accessibilityIdentifier("orgSettings.save")
            .keyboardShortcut("s", modifiers: .command)
    }

    private var saveFooter: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.base)
                    .accessibilityIdentifier("orgSettings.error")
            }
            Button { Task { await vm.save() } } label: {
                Group {
                    if vm.isSaving { ProgressView() } else { Text("Save Changes") }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .padding([.horizontal, .bottom], BrandSpacing.base)
            .disabled(vm.isSaving)
            .accessibilityIdentifier("orgSettings.saveFooter")
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Loading overlay

    @ViewBuilder
    private var loadingOverlay: some View {
        if vm.isLoading {
            ProgressView("Loading…")
                .accessibilityLabel("Loading organisation settings")
        } else if let err = vm.errorMessage, !vm.isSaving {
            ContentUnavailableView {
                Label("Could not load settings", systemImage: "exclamationmark.triangle")
            } description: {
                Text(err)
            } actions: {
                Button("Retry") {
                    Task { await vm.load() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { vm.settings.name },
            set: { vm.updateName($0) }
        )
    }

    private var legalNameBinding: Binding<String> {
        Binding(
            get: { vm.settings.legalName },
            set: { vm.updateLegalName($0) }
        )
    }

    private var addressBinding: Binding<String> {
        Binding(
            get: { vm.settings.address },
            set: { vm.updateField(address: $0) }
        )
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { vm.settings.phone },
            set: { vm.updateField(phone: $0) }
        )
    }

    private var emailBinding: Binding<String> {
        Binding(
            get: { vm.settings.email },
            set: { vm.updateField(email: $0) }
        )
    }

    private var logoUrlBinding: Binding<String> {
        Binding(
            get: { vm.settings.logoUrl },
            set: { vm.updateField(logoUrl: $0) }
        )
    }

    private var taxIdBinding: Binding<String> {
        Binding(
            get: { vm.settings.taxId },
            set: { vm.updateField(taxId: $0) }
        )
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { vm.settings.currencyCode },
            set: { vm.updateField(currencyCode: $0) }
        )
    }

    private var timezoneBinding: Binding<String> {
        Binding(
            get: { vm.settings.timezone },
            set: { vm.updateField(timezone: $0) }
        )
    }

    private var localeBinding: Binding<String> {
        Binding(
            get: { vm.settings.locale },
            set: { vm.updateField(locale: $0) }
        )
    }

    // MARK: - Field helpers

    @ViewBuilder
    private func brandField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .disabled(!canEdit)
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private func padField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(minWidth: 120, alignment: .leading)
            TextField(label, text: text)
                .disabled(!canEdit)
                .textSelection(.enabled)
                .accessibilityLabel(label)
        }
    }
}

// MARK: - GroupBox style

private struct OrganizationGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            configuration.label
                .font(.subheadline.bold())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            configuration.content
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }
}

private extension GroupBoxStyle where Self == OrganizationGroupBoxStyle {
    static var organization: OrganizationGroupBoxStyle { OrganizationGroupBoxStyle() }
}
