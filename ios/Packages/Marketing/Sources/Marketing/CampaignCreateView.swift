import SwiftUI
import Core
import DesignSystem
import Networking

public struct CampaignCreateView: View {
    @State private var vm: CampaignCreateViewModel
    @State private var showAudiencePicker = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: CampaignCreateViewModel(api: api))
    }

    /// Dynamic variables for template insertion (SMS body).
    private let dynamicVars = ["first_name", "last_name", "shop_name", "ticket_no"]

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                formContent
            }
            .navigationTitle("New Campaign")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("Save Draft") {
                            Task {
                                await vm.save()
                                if vm.successCampaign != nil { dismiss() }
                            }
                        }
                        .disabled(!vm.canSubmit && vm.recipientsEstimate == 0)
                        .accessibilityIdentifier("marketing.campaign.saveDraft")
                    }
                }
            }
            .sheet(isPresented: $showAudiencePicker) {
                AudiencePickerSheet(api: api) { selection in
                    switch selection {
                    case .segment(let id, let name, let count):
                        vm.selectSegment(id: id, name: name, count: count)
                    case .smsGroup(let id, let name, let count):
                        vm.selectSmsGroup(id: id, name: name, count: count)
                    case .all:
                        vm.clearAudience()
                    }
                }
            }
        }
        .onChange(of: vm.successCampaign) { _, c in
            if c != nil { dismiss() }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        Form {
            nameSection
            typeSection
            channelSection
            audienceSection
            messageSection
            if vm.needsSubject { subjectSection }
            scheduleSection
            abSection
            if vm.recipientsEstimate > 0 { costSection }
            if let err = vm.errorMessage {
                Section {
                    Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                }
                .listRowBackground(Color.bizarreError.opacity(0.1))
            }
        }
        .scrollContentBackground(.hidden)
        #if canImport(UIKit)
        .background(Color.bizarreSurfaceBase)
        #endif
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Campaign name") {
            TextField("e.g. Summer Re-engagement", text: $vm.name)
                .font(.brandBodyLarge())
                .accessibilityLabel("Campaign name")
                .accessibilityIdentifier("marketing.campaign.name")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var typeSection: some View {
        Section("Type") {
            Picker("Campaign type", selection: $vm.campaignType) {
                ForEach(CampaignType.allCases, id: \.self) { t in
                    Label(t.displayName, systemImage: t.systemImage).tag(t)
                }
            }
            .accessibilityLabel("Campaign type")
            .accessibilityIdentifier("marketing.campaign.type")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var channelSection: some View {
        Section("Channel") {
            Picker("Channel", selection: $vm.channel) {
                ForEach(CampaignChannel.allCases, id: \.self) { c in
                    Label(c.displayName, systemImage: c.systemImage).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Campaign channel")
            .accessibilityIdentifier("marketing.campaign.channel")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var audienceSection: some View {
        Section("Audience") {
            Button {
                showAudiencePicker = true
            } label: {
                HStack {
                    Label(
                        vm.audience.displayName,
                        systemImage: "person.3"
                    )
                    .foregroundStyle(
                        (vm.audience == .all) ? .bizarreOnSurfaceMuted : .bizarreOnSurface
                    )
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Audience: \(vm.audience.displayName)")
            .accessibilityIdentifier("marketing.campaign.audiencePicker")

            if vm.recipientsEstimate > 0 {
                HStack {
                    Text("Recipients").foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text("\(vm.recipientsEstimate)")
                        .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
                }
                .font(.brandBodyMedium())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recipients: \(vm.recipientsEstimate)")

                if vm.requiresApproval {
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreWarning).accessibilityHidden(true)
                        Text("Requires manager approval")
                            .font(.brandLabelSmall()).foregroundStyle(.bizarreWarning)
                    }
                }
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var messageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                TextEditor(text: $vm.template)
                    .font(.brandBodyMedium())
                    .frame(minHeight: 100)
                    .accessibilityLabel("Message body")
                    .accessibilityIdentifier("marketing.campaign.template")

                // Char counter (SMS only)
                if vm.channel != .email {
                    HStack {
                        Text("\(vm.templateCharCount) chars · \(vm.templateSegments) SMS segment(s)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                    }
                }

                // Dynamic variable chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(dynamicVars, id: \.self) { v in
                            Button {
                                vm.insertDynamicVar(v)
                            } label: {
                                Text("{{\(v)}}")
                                    .font(.brandMono(size: 12))
                                    .padding(.horizontal, BrandSpacing.md)
                                    .padding(.vertical, BrandSpacing.xs)
                                    .foregroundStyle(.bizarreOnSurface)
                                    .background(Color.bizarreSurface2, in: Capsule())
                            }
                            .accessibilityLabel("Insert variable \(v)")
                        }
                    }
                }
            }
        } header: {
            Text("Message Body")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var subjectSection: some View {
        Section("Email Subject") {
            TextField("e.g. We miss you!", text: $vm.templateSubject)
                .font(.brandBodyMedium())
                .accessibilityLabel("Email subject")
                .accessibilityIdentifier("marketing.campaign.subject")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Send", selection: scheduleBinding) {
                Text("Send now").tag(0)
                Text("Pick date & time").tag(1)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Schedule option")

            if case .scheduled(let currentDate) = vm.schedule {
                DatePicker(
                    "Send at",
                    selection: Binding(
                        get: { currentDate },
                        set: { vm.schedule = .scheduled($0) }
                    ),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityLabel("Send date and time")
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var scheduleBinding: Binding<Int> {
        Binding {
            if case .now = vm.schedule { return 0 } else { return 1 }
        } set: { v in
            vm.schedule = v == 0 ? .now : .scheduled(Date().addingTimeInterval(3600))
        }
    }

    private var abSection: some View {
        Section {
            Toggle("A/B Test", isOn: $vm.abEnabled)
                .accessibilityLabel("Enable A/B testing")
                .accessibilityIdentifier("marketing.campaign.abToggle")

            if vm.abEnabled {
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    Text("Message B")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextEditor(text: $vm.variantB)
                        .font(.brandBodyMedium())
                        .frame(minHeight: 80)
                        .accessibilityLabel("Message variant B")
                        .accessibilityIdentifier("marketing.campaign.variantB")
                }
            }
        } header: {
            Text("A/B Variants")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var costSection: some View {
        Section("Estimated cost") {
            HStack {
                Label("SMS fees", systemImage: "dollarsign.circle")
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(vm.estimatedCostText)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            .font(.brandBodyMedium())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Estimated cost: \(vm.estimatedCostText)")
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}
