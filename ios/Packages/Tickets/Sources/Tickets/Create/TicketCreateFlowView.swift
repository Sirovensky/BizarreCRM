#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Customers
import UIKit

// §4.3 — Full-fidelity multi-step ticket create.
//
// iPhone: NavigationStack with one full-screen step per push + glass progress
//         bar in the toolbar.
// iPad:   Sheet with 2-column layout: left = step list, right = active step.
//
// Steps: Customer → Devices → Pricing → Assignee/Due → Review
// Offline: uses TicketOfflineQueue (same as minimal create).

public struct TicketCreateFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketCreateFlowViewModel
    @State private var showingCustomerPicker = false
    @State private var pendingBanner: String?
    private let customerRepo: CustomerRepository
    private let onCreated: (_ ticketId: Int64) -> Void
    // §4.3 — Optional "print label" callback. When non-nil and a printer is paired,
    // a "Print intake label" banner is offered after successful create.
    private let onPrintLabel: ((_ ticketId: Int64) -> Void)?

    public init(
        api: APIClient,
        customerRepo: CustomerRepository,
        onCreated: @escaping (_ ticketId: Int64) -> Void = { _ in },
        onPrintLabel: ((_ ticketId: Int64) -> Void)? = nil
    ) {
        self.customerRepo = customerRepo
        self.onCreated = onCreated
        self.onPrintLabel = onPrintLabel
        _vm = State(wrappedValue: TicketCreateFlowViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneFlow
            } else {
                iPadFlow
            }
        }
        .overlay(alignment: .top) {
            if let banner = pendingBanner {
                TicketPendingSyncBanner(text: banner)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // §4.3: inline validation error toast
        .overlay(alignment: .bottom) {
            if let validationError = vm.stepValidationError {
                StepValidationToast(message: validationError)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(BrandMotion.standard, value: vm.stepValidationError)
    }

    // MARK: - iPhone: full-screen NavigationStack

    private var iPhoneFlow: some View {
        NavigationStack {
            stepView(vm.currentStep)
                .navigationTitle(vm.currentStep.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { iPhoneToolbar }
        }
    }

    @ToolbarContentBuilder
    private var iPhoneToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if vm.currentStep == .customer {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(".", modifiers: .command)  // §4.3 ⌘. cancel
                    .accessibilityLabel("Cancel ticket creation")
            } else {
                Button(action: vm.back) {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)  // §4.3 ⌘← prev step
                .accessibilityLabel("Go back to \(prevStepTitle)")
            }
        }

        ToolbarItem(placement: .principal) {
            CreateFlowProgressBar(current: vm.currentStep.rawValue, total: CreateFlowStep.allCases.count)
                .frame(width: 120)
        }

        ToolbarItem(placement: .confirmationAction) {
            if vm.currentStep == .review {
                Button {
                    Task { await submitAndDismiss() }
                } label: {
                    Text(vm.isSubmitting ? "Creating…" : "Create")
                        .fontWeight(.semibold)
                }
                .disabled(!vm.canGoNext || vm.isSubmitting)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Create ticket")
            } else {
                Button("Next", action: vm.next)
                    .disabled(!vm.canGoNext)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .accessibilityLabel("Go to next step")
            }
        }
    }

    // MARK: - iPad: 2-column sheet

    private var iPadFlow: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left: step sidebar
                CreateFlowStepSidebar(currentStep: vm.currentStep)
                    .frame(width: 200)

                Divider()

                // Right: active step
                ScrollView {
                    stepView(vm.currentStep)
                        .padding(BrandSpacing.lg)
                        .frame(maxWidth: 640, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            }
            .navigationTitle("New Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { iPadToolbar }
        }
    }

    @ToolbarContentBuilder
    private var iPadToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(".", modifiers: .command)  // §4.3 ⌘. cancel
                .accessibilityLabel("Cancel ticket creation")
        }

        ToolbarItem(placement: .primaryAction) {
            if vm.currentStep == .review {
                Button {
                    Task { await submitAndDismiss() }
                } label: {
                    Text(vm.isSubmitting ? "Creating…" : "Create Ticket")
                        .fontWeight(.semibold)
                }
                .buttonStyle(BrandGlassProminentButtonStyle())
                .disabled(!vm.canGoNext || vm.isSubmitting)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Create ticket")
            } else {
                Button("Next →", action: vm.next)
                    .disabled(!vm.canGoNext)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .accessibilityLabel("Go to next step")
            }
        }

        ToolbarItem(placement: .secondaryAction) {
            if vm.canGoBack {
                Button("← Back", action: vm.back)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .accessibilityLabel("Go back")
            }
        }
    }

    // MARK: - Step router

    @ViewBuilder
    private func stepView(_ step: CreateFlowStep) -> some View {
        switch step {
        case .customer:
            CustomerStepView(
                selectedCustomer: vm.selectedCustomer,
                onPickCustomer: { vm.selectedCustomer = $0 },
                customerRepo: customerRepo
            )
        case .devices:
            DevicesStepView(vm: vm)
        case .pricing:
            PricingStepView(vm: vm)
        case .schedule:
            ScheduleStepView(vm: vm)
        case .review:
            ReviewStepView(vm: vm)
        }
    }

    // MARK: - Submit

    private func submitAndDismiss() async {
        await vm.submit()
        if let id = vm.createdTicketId {
            // §4.3: .success haptic on create
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            if vm.queuedOffline {
                pendingBanner = "Saved — will sync when online"
                generator.notificationOccurred(.success)
                try? await Task.sleep(nanoseconds: 900_000_000)
            } else {
                generator.notificationOccurred(.success)
            }
            // §4.3 — Post-create: pop to ticket detail + offer "Print label" if callback available
            onCreated(id)
            if let printLabel = onPrintLabel {
                // Brief banner so the view is still visible before dismiss
                pendingBanner = "Ticket created — tap to print intake label"
                try? await Task.sleep(nanoseconds: 600_000_000)
                printLabel(id)
            }
            dismiss()
        } else if vm.errorMessage != nil {
            // §4.3: .error haptic on validation fail / server error
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }

    // MARK: - Helpers

    private var prevStepTitle: String {
        let all = CreateFlowStep.allCases
        guard let idx = all.firstIndex(of: vm.currentStep), idx > 0 else { return "" }
        return all[idx - 1].title
    }
}

// MARK: - §4.3 Inline validation toast (glass error pill)

private struct CreateFlowValidationToast: View {
    let message: String

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bizarreError.opacity(0.9), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Validation error: \(message)")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Progress bar (chrome only)

private struct CreateFlowProgressBar: View {
    let current: Int    // 0-based
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.bizarreSurface1)
                    .frame(height: 4)
                Capsule()
                    .fill(Color.bizarreOrange)
                    .frame(width: progress(geo.size.width), height: 4)
                    .animation(BrandMotion.stepTransition, value: current)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }

    private func progress(_ width: CGFloat) -> CGFloat {
        guard total > 1 else { return width }
        return width * CGFloat(current + 1) / CGFloat(total)
    }
}

// MARK: - Step sidebar (iPad only)

private struct CreateFlowStepSidebar: View {
    let currentStep: CreateFlowStep

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CreateFlowStep.allCases, id: \.self) { step in
                HStack(spacing: BrandSpacing.sm) {
                    Circle()
                        .fill(step == currentStep ? Color.bizarreOrange : Color.bizarreSurface1)
                        .frame(width: 8, height: 8)
                    Text(step.title)
                        .font(.brandBodyMedium())
                        .foregroundStyle(step == currentStep ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
                .background(step == currentStep ? Color.bizarreOrange.opacity(0.08) : Color.clear)
                .accessibilityAddTraits(step == currentStep ? .isSelected : [])
            }
            Spacer()
        }
        .background(Color.bizarreSurface1.ignoresSafeArea())
    }
}

// MARK: - Step 1: Customer

private struct CustomerStepView: View {
    let selectedCustomer: CustomerSummary?
    let onPickCustomer: (CustomerSummary) -> Void
    let customerRepo: CustomerRepository

    @State private var showingPicker = false

    var body: some View {
        Form {
            Section("Customer") {
                if let customer = selectedCustomer {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.bizarreOrange)
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            Text(customer.displayName)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            if let line = customer.contactLine {
                                Text(line)
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        Spacer()
                        Button("Change") { showingPicker = true }
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOrange)
                    }
                    .padding(.vertical, BrandSpacing.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Selected customer: \(customer.displayName)")
                } else {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Text("Choose customer")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose customer")
                    .accessibilityHint("Opens customer picker")
                }
            }

            if selectedCustomer == nil {
                Section {
                    Text("A customer is required to create a ticket.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .sheet(isPresented: $showingPicker) {
            FlowCustomerPickerSheet(repo: customerRepo, onPick: { customer in
                onPickCustomer(customer)
                showingPicker = false
            })
        }
    }
}

private struct FlowCustomerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var listVm: CustomerListViewModel
    @State private var searchText: String = ""
    let onPick: (CustomerSummary) -> Void

    init(repo: CustomerRepository, onPick: @escaping (CustomerSummary) -> Void) {
        _listVm = State(wrappedValue: CustomerListViewModel(repo: repo))
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            Group {
                if listVm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if listVm.customers.isEmpty {
                    ContentUnavailableView(
                        "No customers",
                        systemImage: "person.2",
                        description: Text("Search above or create a customer first.")
                    )
                } else {
                    List {
                        ForEach(listVm.customers) { c in
                            Button { onPick(c) } label: {
                                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                    Text(c.displayName).foregroundStyle(.bizarreOnSurface)
                                    if let line = c.contactLine {
                                        Text(line)
                                            .font(.brandLabelSmall())
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Customer: \(c.displayName)")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Choose Customer")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search customers")
            .onChange(of: searchText) { _, new in listVm.onSearchChange(new) }
            .task { await listVm.load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Step 2: Devices

private struct ServicePickerTarget: Identifiable { let id: Int }  // wraps device index
private struct CatalogPickerTarget: Identifiable { let id: Int }  // wraps device index

private struct DevicesStepView: View {
    @Bindable var vm: TicketCreateFlowViewModel
    @State private var servicePickerTarget: ServicePickerTarget? = nil
    @State private var catalogPickerTarget: CatalogPickerTarget? = nil

    var body: some View {
        Form {
            ForEach(Array(vm.devices.enumerated()), id: \.element.id) { idx, device in
                Section {
                    DeviceFormSection(
                        device: device,
                        onUpdate: { update in vm.updateDevice(at: idx, update) },
                        onToggleChecklist: { itemId in vm.toggleChecklistItem(deviceIndex: idx, itemId: itemId) },
                        onPickService: { servicePickerTarget = ServicePickerTarget(id: idx) },
                        onPickCatalogDevice: { catalogPickerTarget = CatalogPickerTarget(id: idx) }
                    )

                    if vm.devices.count > 1 {
                        Button(role: .destructive) {
                            vm.removeDevice(at: idx)
                        } label: {
                            Label("Remove this device", systemImage: "trash")
                                .foregroundStyle(.bizarreError)
                        }
                        .accessibilityLabel("Remove device \(idx + 1)")
                    }
                } header: {
                    Text(vm.devices.count > 1 ? "Device \(idx + 1)" : "Device")
                }
            }

            Section {
                Button {
                    vm.addDevice()
                } label: {
                    Label("Add another device", systemImage: "plus.circle")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add another device to this ticket")
            }

            if vm.currentStep == .devices, !vm.stepValid {
                Section {
                    Text("Each device needs a name.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .sheet(item: $servicePickerTarget) { target in
            // §4.3 — Services / parts picker for device at target.id
            TicketCreateServicePickerSheet(api: vm.api) { serviceId, name, price in
                vm.updateDevice(at: target.id) {
                    $0.serviceId = serviceId
                    $0.serviceName = name
                    if $0.price == 0 { $0.price = price }   // pre-fill price only if blank
                }
                servicePickerTarget = nil
            }
        }
        .sheet(item: $catalogPickerTarget) { target in
            // §4.3 — Device catalog hierarchical picker
            CatalogDevicePickerSheet(api: vm.api) { catalogDevice in
                vm.updateDevice(at: target.id) {
                    // Pre-fill device name from catalog selection if blank
                    if $0.deviceName.isEmpty {
                        $0.deviceName = catalogDevice.displayName
                    }
                }
                catalogPickerTarget = nil
            }
        }
    }
}

private struct DeviceFormSection: View {
    var device: DraftDevice
    let onUpdate: ((inout DraftDevice) -> Void) -> Void
    let onToggleChecklist: (String) -> Void
    let onPickService: () -> Void
    let onPickCatalogDevice: () -> Void

    var body: some View {
        Group {
            // §4.3 — Device name with catalog lookup shortcut
            HStack {
                TextField("Device name (e.g. iPhone 14 Pro)", text: .init(
                    get: { device.deviceName },
                    set: { v in onUpdate { $0.deviceName = v } }
                ))
                .autocorrectionDisabled()
                .accessibilityLabel("Device name")
                Button {
                    onPickCatalogDevice()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Look up device in catalog")
            }

            TextField("IMEI", text: .init(
                get: { device.imei },
                set: { v in onUpdate { $0.imei = v } }
            ))
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
            .accessibilityLabel("IMEI number")

            TextField("Serial number", text: .init(
                get: { device.serial },
                set: { v in onUpdate { $0.serial = v } }
            ))
            .autocorrectionDisabled()
            .accessibilityLabel("Serial number")

            TextField("Security code / pattern", text: .init(
                get: { device.securityCode },
                set: { v in onUpdate { $0.securityCode = v } }
            ))
            .autocorrectionDisabled()
            .accessibilityLabel("Device security code")

            TextField("Issue / customer said…", text: .init(
                get: { device.additionalNotes },
                set: { v in onUpdate { $0.additionalNotes = v } }
            ), axis: .vertical)
            .lineLimit(2...4)
            .accessibilityLabel("Device issue description")

            TextField("Repair price (USD)", text: .init(
                get: { device.price == 0 ? "" : String(device.price) },
                set: { v in onUpdate { $0.price = Double(v.replacingOccurrences(of: ",", with: ".")) ?? 0 } }
            ))
            .keyboardType(.decimalPad)
            .accessibilityLabel("Repair price in US dollars")

            // §4.3 — Service picker shortcut
            Button {
                onPickService()
            } label: {
                HStack {
                    if !device.serviceName.isEmpty {
                        Text(device.serviceName)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    } else {
                        Text("Choose repair service…")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(device.serviceName.isEmpty ? "Choose a repair service from catalog" : "Selected service: \(device.serviceName). Tap to change.")
        }

        // Pre-conditions checklist
        ChecklistSection(items: device.checklist, onToggle: onToggleChecklist)
    }
}

private struct ChecklistSection: View {
    let items: [ChecklistItem]
    let onToggle: (String) -> Void

    var body: some View {
        Section("Pre-conditions intake") {
            ForEach(items) { item in
                Button {
                    onToggle(item.id)
                } label: {
                    HStack {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.checked ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        Text(item.label)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityValue(item.checked ? "checked" : "unchecked")
                .accessibilityHint("Toggle checklist item")
            }
        }
    }
}

// MARK: - Step 3: Pricing

private struct PricingStepView: View {
    @Bindable var vm: TicketCreateFlowViewModel

    var body: some View {
        Form {
            Section("Line items") {
                ForEach(Array(vm.devices.enumerated()), id: \.element.id) { idx, device in
                    HStack {
                        Text(device.deviceName.isEmpty ? "Device \(idx + 1)" : device.deviceName)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(formatCurrency(device.price))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(device.deviceName.isEmpty ? "Device \(idx + 1)" : device.deviceName): \(formatCurrency(device.price))")
                }
            }

            Section("Discount") {
                Picker("Discount type", selection: $vm.discountMode) {
                    ForEach(TicketCreateFlowViewModel.DiscountMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Discount type")

                TextField(
                    vm.discountMode == .absolute ? "Discount amount (USD)" : "Discount percentage",
                    text: $vm.discountText
                )
                .keyboardType(.decimalPad)
                .accessibilityLabel("Discount value")

                if vm.discountAmount > 0 {
                    LabeledContent("Discount", value: "−\(formatCurrency(vm.discountAmount))")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Discount: minus \(formatCurrency(vm.discountAmount))")
                }

                TextField("Reason (if applicable)", text: $vm.discountReason)
                    .accessibilityLabel("Discount reason")
            }

            Section("Totals") {
                LabeledContent("Subtotal", value: formatCurrency(vm.subtotal))
                    .textSelection(.enabled)
                    .accessibilityLabel("Subtotal: \(formatCurrency(vm.subtotal))")

                if vm.discountAmount > 0 {
                    LabeledContent("Discount", value: "−\(formatCurrency(vm.discountAmount))")
                        .foregroundStyle(.bizarreError)
                }

                Divider()

                LabeledContent("Estimate total", value: formatCurrency(vm.grandTotal))
                    .font(.brandBodyLarge())
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
                    .accessibilityLabel("Estimated total: \(formatCurrency(vm.grandTotal))")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
}

// MARK: - Step 4: Assignee, Due Date, Service Type, Tags

private struct ScheduleStepView: View {
    @Bindable var vm: TicketCreateFlowViewModel
    @State private var newTag: String = ""

    var body: some View {
        Form {
            Section("Assignee") {
                if !vm.assignedEmployeeName.isEmpty {
                    HStack {
                        Image(systemName: "person.fill.checkmark")
                            .foregroundStyle(.bizarreOrange)
                        Text(vm.assignedEmployeeName)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Button("Clear") {
                            vm.assignedEmployeeId = nil
                            vm.assignedEmployeeName = ""
                        }
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Assigned to: \(vm.assignedEmployeeName)")
                } else {
                    HStack {
                        Image(systemName: "person.circle")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("Unassigned")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .accessibilityLabel("No assignee selected")
                }
            }

            Section("Scheduling") {
                TextField("Due date (YYYY-MM-DD)", text: $vm.dueOn)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Due date in year month day format")
            }

            // §4.3 — Service type picker
            Section("Service type") {
                Picker("Service type", selection: $vm.serviceType) {
                    Text("None").tag(Optional<TicketServiceType>.none)
                    ForEach(TicketServiceType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(Optional(t))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Ticket service type")
            }

            // §4.3 — Tags multi-chip
            Section("Tags / labels") {
                if !vm.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: BrandSpacing.xs) {
                            ForEach(vm.tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                        .font(.brandLabelSmall())
                                    Button {
                                        vm.tags.removeAll { $0 == tag }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                    }
                                    .accessibilityLabel("Remove tag \(tag)")
                                }
                                .padding(.horizontal, BrandSpacing.sm)
                                .padding(.vertical, BrandSpacing.xxs)
                                .background(Color.bizarreOrange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.bizarreOnSurface)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Tag: \(tag)")
                            }
                        }
                        .padding(.vertical, BrandSpacing.xs)
                    }
                }
                HStack {
                    TextField("Add tag…", text: $newTag)
                        .submitLabel(.done)
                        .onSubmit { addTag() }
                        .accessibilityLabel("New tag name")
                    if !newTag.isEmpty {
                        Button("Add") { addTag() }
                            .foregroundStyle(.bizarreOrange)
                            .font(.brandLabelMedium())
                            .accessibilityLabel("Add tag")
                    }
                }
            }

            Section("Classification") {
                TextField("Source (walk-in, web, referral…)", text: $vm.source)
                    .accessibilityLabel("Ticket source")
                TextField("Referral source", text: $vm.referralSource)
                    .accessibilityLabel("Referral source")
            }

            // §4.3 — Deposit
            Section("Deposit") {
                HStack {
                    Text("$")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("0.00", value: $vm.depositAmount, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Deposit amount in dollars")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !vm.tags.contains(trimmed) else {
            newTag = ""
            return
        }
        vm.tags.append(trimmed)
        newTag = ""
    }
}

// MARK: - Step 5: Review

private struct ReviewStepView: View {
    let vm: TicketCreateFlowViewModel

    var body: some View {
        Form {
            if let customer = vm.selectedCustomer {
                Section("Customer") {
                    LabeledContent("Name", value: customer.displayName)
                        .textSelection(.enabled)
                    if let line = customer.contactLine {
                        LabeledContent("Contact", value: line)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Devices (\(vm.devices.count))") {
                ForEach(Array(vm.devices.enumerated()), id: \.element.id) { idx, device in
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text(device.deviceName.isEmpty ? "Device \(idx + 1)" : device.deviceName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        if !device.imei.isEmpty {
                            Text("IMEI: \(device.imei)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .textSelection(.enabled)
                        }
                        if !device.additionalNotes.isEmpty {
                            Text(device.additionalNotes)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .padding(.vertical, BrandSpacing.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Device \(idx + 1): \(device.deviceName)")
                }
            }

            Section("Pricing") {
                LabeledContent("Subtotal", value: formatCurrency(vm.subtotal))
                    .textSelection(.enabled)
                if vm.discountAmount > 0 {
                    LabeledContent("Discount", value: "−\(formatCurrency(vm.discountAmount))")
                        .foregroundStyle(.bizarreError)
                }
                LabeledContent("Total", value: formatCurrency(vm.grandTotal))
                    .font(.brandBodyLarge())
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
            }

            if !vm.assignedEmployeeName.isEmpty || !vm.dueOn.isEmpty {
                Section("Schedule") {
                    if !vm.assignedEmployeeName.isEmpty {
                        LabeledContent("Assigned to", value: vm.assignedEmployeeName)
                    }
                    if !vm.dueOn.isEmpty {
                        LabeledContent("Due", value: vm.dueOn)
                    }
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.bizarreError)
                        .font(.brandBodyMedium())
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
}

// MARK: - BrandMotion extension for step transition

private extension Animation {
    static var `default`: Animation { .easeInOut(duration: 0.22) }
}

private extension BrandMotion {
    static var stepTransition: Animation { .easeInOut(duration: DesignTokens.Motion.snappy) }
}

// MARK: - §4.3 Inline glass validation toast

/// Glass pill that appears at the bottom of the create flow when a step
/// validation fails. Auto-dismissed when the user corrects the field and
/// the stepValidationError is cleared by the ViewModel.
private struct StepValidationToast: View {
    let message: String

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreError.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Validation error: \(message)")
        .accessibilityAddTraits(.isStaticText)
    }
}
#endif
