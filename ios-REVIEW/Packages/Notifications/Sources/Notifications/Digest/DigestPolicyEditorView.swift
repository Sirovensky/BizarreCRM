import SwiftUI
import Observation
import DesignSystem

// MARK: - DigestPolicyEditorViewModel

@MainActor
@Observable
public final class DigestPolicyEditorViewModel {

    public private(set) var policy: DigestPolicy
    public var selectedHour: Int
    public var selectedMinute: Int

    public init(policy: DigestPolicy = DigestPolicy()) {
        self.policy = policy
        self.selectedHour = policy.sendTime.hour
        self.selectedMinute = policy.sendTime.minute
    }

    // MARK: - Editing

    public func toggleCategory(_ cat: EventCategory) {
        if policy.includedCategories.contains(cat) {
            policy = policy.excludingCategory(cat)
        } else {
            policy = policy.includingCategory(cat)
        }
    }

    public func commitTime() {
        let time = DigestTime(hour: selectedHour, minute: selectedMinute)
        policy = policy.withSendTime(time)
    }

    public func setEnabled(_ enabled: Bool) {
        policy = policy.withEnabled(enabled)
    }

    public var previewSendTime: String { policy.sendTime.displayString }
}

// MARK: - DigestPolicyEditorView

/// Editor: pick digest send time + which categories to include.
public struct DigestPolicyEditorView: View {

    @State private var vm: DigestPolicyEditorViewModel
    let onSave: (DigestPolicy) -> Void

    public init(
        viewModel: DigestPolicyEditorViewModel = DigestPolicyEditorViewModel(),
        onSave: @escaping (DigestPolicy) -> Void = { _ in }
    ) {
        _vm = State(wrappedValue: viewModel)
        self.onSave = onSave
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            form
        }
        .navigationTitle("Daily Digest")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { saveButton }
    }

    @ViewBuilder
    private var form: some View {
        List {
            enableSection
            timeSection
            categoriesSection
            previewSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Enable toggle

    @ViewBuilder
    private var enableSection: some View {
        Section {
            Toggle("Enable Daily Digest", isOn: Binding(
                get: { vm.policy.isEnabled },
                set: { vm.setEnabled($0) }
            ))
            .tint(.bizarreOrange)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("Enable daily digest notification")
        } footer: {
            Text("A single summary push at your chosen time, instead of individual notifications for low-priority events.")
                .font(.brandBodySmall())
        }
    }

    // MARK: - Time picker

    @ViewBuilder
    private var timeSection: some View {
        Section("Send Time") {
            HStack {
                Picker("Hour", selection: $vm.selectedHour) {
                    ForEach(0..<24, id: \.self) { h in
                        let label = h < 12 ? "\(h == 0 ? 12 : h) AM" : "\(h == 12 ? 12 : h - 12) PM"
                        Text(label).tag(h)
                    }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #else
                .pickerStyle(.menu)
                #endif
                .frame(maxWidth: .infinity)
                .onChange(of: vm.selectedHour) { _, _ in vm.commitTime() }

                Picker("Minute", selection: $vm.selectedMinute) {
                    ForEach([0, 15, 30, 45], id: \.self) { m in
                        Text(String(format: ":%02d", m)).tag(m)
                    }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #else
                .pickerStyle(.menu)
                #endif
                .frame(width: 80)
                .onChange(of: vm.selectedMinute) { _, _ in vm.commitTime() }
            }
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("Select digest send time")
        }
    }

    // MARK: - Category toggles

    @ViewBuilder
    private var categoriesSection: some View {
        Section("Include Categories") {
            ForEach(EventCategory.allCases, id: \.rawValue) { cat in
                let included = vm.policy.includedCategories.contains(cat)
                Toggle(cat.rawValue, isOn: Binding(
                    get: { included },
                    set: { _ in vm.toggleCategory(cat) }
                ))
                .tint(.bizarreOrange)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityLabel("\(cat.rawValue) \(included ? "included in digest" : "excluded from digest")")
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        Section("Preview") {
            NotificationDigestPreviewView(
                items: [
                    DigestSummaryItem(category: .tickets, count: 3),
                    DigestSummaryItem(category: .communications, count: 2)
                ],
                digestTime: vm.policy.sendTime
            )
            .listRowBackground(Color.clear)
            .listRowInsets(.init())
            .padding(.vertical, BrandSpacing.xs)
        }
    }

    // MARK: - Save

    @ToolbarContentBuilder
    private var saveButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { onSave(vm.policy) }
                .fontWeight(.semibold)
                .accessibilityLabel("Save digest policy")
        }
    }
}

// MARK: - Font helper

private extension Font {
    static func brandBodySmall() -> Font { .system(size: 13) }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        DigestPolicyEditorView()
    }
}
#endif
