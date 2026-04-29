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
            documentFooterSection       // §19.5
            termsAndPoliciesSection     // §19.5 Terms & policies
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
                alignment: .leading,
                spacing: BrandSpacing.lg
            ) {
                identityCard
                contactCard
                localisationCard
                documentFooterCard      // §19.5
                termsAndPoliciesCard    // §19.5 Terms & policies
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

    // MARK: §19.5 Document footers section + card

    private var documentFooterSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Receipt footer")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextEditor(text: receiptFooterBinding)
                    .frame(minHeight: 72, maxHeight: 120)
                    .disabled(!canEdit)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .scrollContentBackground(.hidden)
                    .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("org.receiptFooter")
                    .accessibilityLabel("Receipt footer text")
            }
            .listRowBackground(Color.bizarreSurface1)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Invoice footer")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextEditor(text: invoiceFooterBinding)
                    .frame(minHeight: 72, maxHeight: 160)
                    .disabled(!canEdit)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .scrollContentBackground(.hidden)
                    .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("org.invoiceFooter")
                    .accessibilityLabel("Invoice footer text")
            }
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Document Footers")
        } footer: {
            Text("Text shown at the bottom of receipts and invoices. Supports line breaks.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: §19.5 Terms & policies — printed on receipts (warranty, return, privacy)

    private var termsAndPoliciesSection: some View {
        Section {
            policyEditor(
                title: "Warranty policy",
                identifier: "org.warrantyPolicy",
                placeholder: "All repairs include a 90-day limited warranty…",
                binding: warrantyPolicyBinding,
                minHeight: 72,
                maxHeight: 140
            )
            policyEditor(
                title: "Return policy",
                identifier: "org.returnPolicy",
                placeholder: "Returns accepted within 14 days with original receipt…",
                binding: returnPolicyBinding,
                minHeight: 72,
                maxHeight: 140
            )
            policyEditor(
                title: "Privacy policy",
                identifier: "org.privacyPolicy",
                placeholder: "Customer data is never sold. See bizarrecrm.com/privacy…",
                binding: privacyPolicyBinding,
                minHeight: 72,
                maxHeight: 140
            )
        } header: {
            Text("Terms & Policies")
        } footer: {
            Text("Printed on receipts. Keep brief; long policies should link to a public URL.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var termsAndPoliciesCard: some View {
        GroupBox("Terms & Policies") {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                policyEditor(
                    title: "Warranty policy",
                    identifier: "org.warrantyPolicy.pad",
                    placeholder: "90-day limited warranty…",
                    binding: warrantyPolicyBinding,
                    minHeight: 64,
                    maxHeight: 120
                )
                policyEditor(
                    title: "Return policy",
                    identifier: "org.returnPolicy.pad",
                    placeholder: "Returns within 14 days…",
                    binding: returnPolicyBinding,
                    minHeight: 64,
                    maxHeight: 120
                )
                policyEditor(
                    title: "Privacy policy",
                    identifier: "org.privacyPolicy.pad",
                    placeholder: "Customer data handling…",
                    binding: privacyPolicyBinding,
                    minHeight: 64,
                    maxHeight: 120
                )
            }
        }
        .groupBoxStyle(.organization)
    }

    @ViewBuilder
    private func policyEditor(
        title: String,
        identifier: String,
        placeholder: String,
        binding: Binding<String>,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            ZStack(alignment: .topLeading) {
                if binding.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.6))
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, BrandSpacing.xs + 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: binding)
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
                    .disabled(!canEdit)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .scrollContentBackground(.hidden)
                    .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(identifier)
                    .accessibilityLabel(title)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var documentFooterCard: some View {
        GroupBox("Document Footers") {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Receipt footer")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextEditor(text: receiptFooterBinding)
                        .frame(minHeight: 64, maxHeight: 100)
                        .disabled(!canEdit)
                        .font(.brandBodyMedium())
                        .scrollContentBackground(.hidden)
                        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Receipt footer text")
                }
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Invoice footer")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextEditor(text: invoiceFooterBinding)
                        .frame(minHeight: 80, maxHeight: 140)
                        .disabled(!canEdit)
                        .font(.brandBodyMedium())
                        .scrollContentBackground(.hidden)
                        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Invoice footer text")
                }
            }
        }
        .groupBoxStyle(.organization)
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

    // §19.5 document-footer bindings
    private var receiptFooterBinding: Binding<String> {
        Binding(
            get: { vm.settings.receiptFooter },
            set: { vm.updateField(receiptFooter: $0) }
        )
    }

    private var invoiceFooterBinding: Binding<String> {
        Binding(
            get: { vm.settings.invoiceFooter },
            set: { vm.updateField(invoiceFooter: $0) }
        )
    }

    // §19.5 Terms & policies bindings
    private var warrantyPolicyBinding: Binding<String> {
        Binding(
            get: { vm.settings.warrantyPolicy },
            set: { vm.updateField(warrantyPolicy: $0) }
        )
    }

    private var returnPolicyBinding: Binding<String> {
        Binding(
            get: { vm.settings.returnPolicy },
            set: { vm.updateField(returnPolicy: $0) }
        )
    }

    private var privacyPolicyBinding: Binding<String> {
        Binding(
            get: { vm.settings.privacyPolicy },
            set: { vm.updateField(privacyPolicy: $0) }
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
