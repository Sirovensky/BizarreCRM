#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

// §5.4 — Tag nesting hierarchy (e.g. "wholesale > region > east") with
// drill-down filters, and saved tag-combo segments reusable by §37 marketing
// and §6.3 pricing.

// MARK: - CustomerTagSegment

/// A saved segment combining tag conditions + scalar filters.
public struct CustomerTagSegment: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    /// AND-combined tags. Customer must have ALL of these.
    public var requiredTags: [String]
    /// OR-combined tags. Customer must have at least one if non-empty.
    public var anyTags: [String]
    /// Optional max days since last visit for segment membership.
    public var maxDaysSinceLastVisit: Int?
    /// Optional minimum lifetime-value cents.
    public var minLTVCents: Int?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        requiredTags: [String] = [],
        anyTags: [String] = [],
        maxDaysSinceLastVisit: Int? = nil,
        minLTVCents: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.requiredTags = requiredTags
        self.anyTags = anyTags
        self.maxDaysSinceLastVisit = maxDaysSinceLastVisit
        self.minLTVCents = minLTVCents
        self.createdAt = createdAt
    }

    /// Init from networking DTO.
    public init(dto: CustomerTagSegmentDTO) {
        self.id = dto.id.isEmpty ? UUID().uuidString : dto.id
        self.name = dto.name
        self.requiredTags = dto.requiredTags
        self.anyTags = dto.anyTags
        self.maxDaysSinceLastVisit = dto.maxDaysSinceLastVisit
        self.minLTVCents = dto.minLTVCents
        self.createdAt = dto.createdAt ?? Date()
    }

    /// Convert to networking DTO.
    public func toDTO() -> CustomerTagSegmentDTO {
        CustomerTagSegmentDTO(
            id: id,
            name: name,
            requiredTags: requiredTags,
            anyTags: anyTags,
            maxDaysSinceLastVisit: maxDaysSinceLastVisit,
            minLTVCents: minLTVCents,
            createdAt: createdAt
        )
    }

    /// Human-readable summary of the segment conditions.
    public var summary: String {
        var parts: [String] = []
        if !requiredTags.isEmpty {
            parts.append("Tags: \(requiredTags.joined(separator: " + "))")
        }
        if !anyTags.isEmpty {
            parts.append("Any of: \(anyTags.joined(separator: ", "))")
        }
        if let days = maxDaysSinceLastVisit {
            parts.append("Last visit < \(days)d")
        }
        if let ltv = minLTVCents {
            parts.append("LTV ≥ $\(ltv / 100)")
        }
        return parts.isEmpty ? "All customers" : parts.joined(separator: " · ")
    }
}

// MARK: - CustomerTagNode

/// A node in the tag nesting hierarchy (e.g. "wholesale > region > east").
/// Tags use "/" as the path separator: "wholesale/region/east".
public struct CustomerTagNode: Identifiable, Sendable {
    public let id: String  // full path
    public let label: String  // last path component
    public let depth: Int
    public var children: [CustomerTagNode]

    public var displayPath: String { id.replacingOccurrences(of: "/", with: " › ") }

    /// Build a tree from a flat list of "/"-delimited tag strings.
    public static func buildTree(from tags: [String]) -> [CustomerTagNode] {
        var roots: [String: CustomerTagNode] = [:]
        for tag in tags.sorted() {
            let components = tag.split(separator: "/").map(String.init)
            insert(components: components, into: &roots, depth: 0)
        }
        return roots.values.sorted(by: { $0.label < $1.label })
    }

    private static func insert(components: [String], into dict: inout [String: CustomerTagNode], depth: Int) {
        guard let first = components.first else { return }
        let fullPath = components.prefix(depth + 1).joined(separator: "/")
        if dict[first] == nil {
            dict[first] = CustomerTagNode(id: fullPath, label: first, depth: depth, children: [])
        }
        if components.count > 1 {
            var remaining = components
            remaining.removeFirst()
            var node = dict[first]!
            insert(components: remaining, into: &node.children, depth: depth + 1)
            dict[first] = node
        }
    }

    // mutable children support
    private static func insert(components: [String], into array: inout [CustomerTagNode], depth: Int) {
        guard let first = components.first else { return }
        let fullPath = components.prefix(depth + 1).joined(separator: "/")
        if let idx = array.firstIndex(where: { $0.label == first }) {
            if components.count > 1 {
                var remaining = components; remaining.removeFirst()
                insert(components: remaining, into: &array[idx].children, depth: depth + 1)
            }
        } else {
            var node = CustomerTagNode(id: fullPath, label: first, depth: depth, children: [])
            if components.count > 1 {
                var remaining = components; remaining.removeFirst()
                insert(components: remaining, into: &node.children, depth: depth + 1)
            }
            array.append(node)
        }
    }
}

// MARK: - CustomerTagSegmentViewModel

@Observable
@MainActor
public final class CustomerTagSegmentViewModel {
    public var segments: [CustomerTagSegment] = []
    public var isLoading = false
    public var errorMessage: String?
    // Editor
    public var isEditing = false
    public var editingSegment: CustomerTagSegment = .init(name: "")
    // Tag drill-down
    public var availableTags: [String] = []
    public var expandedNodes: Set<String> = []

    public var tagTree: [CustomerTagNode] { CustomerTagNode.buildTree(from: availableTags) }

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let dtos = api.listCustomerSegments()
            async let tags = api.listCustomerTags()
            let (loadedDTOs, loadedTags) = try await (dtos, tags)
            segments = loadedDTOs.map(CustomerTagSegment.init(dto:))
            availableTags = loadedTags
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Save

    public func saveSegment() async {
        do {
            let dto = editingSegment.toDTO()
            let savedDTO = try await api.saveCustomerSegment(dto)
            let saved = CustomerTagSegment(dto: savedDTO)
            if let idx = segments.firstIndex(where: { $0.id == saved.id }) {
                segments[idx] = saved
            } else {
                segments.append(saved)
            }
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete

    public func deleteSegment(_ segment: CustomerTagSegment) async {
        do {
            try await api.deleteCustomerSegment(id: segment.id)
            segments.removeAll { $0.id == segment.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startNew() {
        editingSegment = .init(name: "")
        isEditing = true
    }

    public func startEdit(_ segment: CustomerTagSegment) {
        editingSegment = segment
        isEditing = true
    }
}

// MARK: - CustomerTagSegmentView

/// §5.4 — Saved segments view. Lists segments with their tag-combo conditions.
/// Used by §37 Marketing audience builder and §6.3 pricing (read-only import).
public struct CustomerTagSegmentView: View {
    @State private var vm: CustomerTagSegmentViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(api: APIClient) {
        _vm = State(initialValue: CustomerTagSegmentViewModel(api: api))
    }

    public var body: some View {
        Group {
            if hSizeClass == .regular {
                ipadLayout
            } else {
                iphoneLayout
            }
        }
        .navigationTitle("Customer Segments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.startNew() } label: {
                    Label("New Segment", systemImage: "plus")
                }
                .accessibilityLabel("Create new customer segment")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.isEditing) {
            CustomerTagSegmentEditorSheet(vm: vm)
        }
    }

    // MARK: - iPhone layout

    private var iphoneLayout: some View {
        List {
            segmentRows
        }
        .listStyle(.insetGrouped)
        .overlay {
            if vm.isLoading { ProgressView() }
            else if vm.segments.isEmpty { emptyState }
        }
    }

    // MARK: - iPad layout

    private var ipadLayout: some View {
        List {
            segmentRows
        }
        .listStyle(.sidebar)
        .overlay {
            if vm.isLoading { ProgressView() }
            else if vm.segments.isEmpty { emptyState }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var segmentRows: some View {
        ForEach(vm.segments) { segment in
            segmentRow(segment)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await vm.deleteSegment(segment) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { vm.startEdit(segment) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.bizarreOrange)
                }
        }
    }

    private func segmentRow(_ segment: CustomerTagSegment) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(segment.name)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            Text(segment.summary)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(2)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(segment.name). \(segment.summary)")
        .accessibilityHint("Swipe to edit or delete")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "tag.slash")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Segments Yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Create a segment to group customers by tag combinations for marketing campaigns and pricing rules.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button { vm.startNew() } label: {
                Label("Create Segment", systemImage: "plus")
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .accessibilityLabel("Create your first customer segment")
        }
        .padding()
    }
}

// MARK: - CustomerTagSegmentEditorSheet

/// Sheet for creating or editing a tag-combo segment with drill-down tag picker.
public struct CustomerTagSegmentEditorSheet: View {
    @Bindable var vm: CustomerTagSegmentViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            Form {
                // Name
                Section("Name") {
                    TextField("e.g. VIP + last visit < 90d", text: $vm.editingSegment.name)
                        .accessibilityLabel("Segment name")
                }

                // Required tags (AND)
                Section {
                    tagPickerSection(
                        title: "Must have ALL tags",
                        tags: $vm.editingSegment.requiredTags
                    )
                } header: {
                    Text("Required Tags (AND)")
                } footer: {
                    Text("Customer must match every tag listed here.")
                        .font(.brandLabelSmall())
                }

                // Any tags (OR)
                Section {
                    tagPickerSection(
                        title: "Must have any tag",
                        tags: $vm.editingSegment.anyTags
                    )
                } header: {
                    Text("Any Tags (OR)")
                } footer: {
                    Text("Customer must match at least one tag here (if any are set).")
                        .font(.brandLabelSmall())
                }

                // Scalar filters
                Section("Optional Filters") {
                    LabeledContent("Last visit within (days)") {
                        TextField("e.g. 90", value: $vm.editingSegment.maxDaysSinceLastVisit, format: .number)
                            .multilineTextAlignment(.trailing)
                            #if canImport(UIKit)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    .accessibilityLabel("Max days since last visit")

                    LabeledContent("Min lifetime value ($)") {
                        TextField("e.g. 500", value: Binding(
                            get: { vm.editingSegment.minLTVCents.map { $0 / 100 } },
                            set: { vm.editingSegment.minLTVCents = $0.map { $0 * 100 } }
                        ), format: .number)
                        .multilineTextAlignment(.trailing)
                        #if canImport(UIKit)
                        .keyboardType(.numberPad)
                        #endif
                    }
                    .accessibilityLabel("Minimum lifetime value in dollars")
                }

                // Tag tree drill-down
                if !vm.tagTree.isEmpty {
                    Section("Tag Browser") {
                        ForEach(vm.tagTree, id: \.id) { node in
                            tagNodeRow(node, binding: $vm.editingSegment.requiredTags)
                        }
                    }
                }

                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .navigationTitle(vm.editingSegment.id.isEmpty ? "New Segment" : "Edit Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await vm.saveSegment() }
                    }
                    .disabled(vm.editingSegment.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Tag pill row

    private func tagPickerSection(title: String, tags: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if tags.wrappedValue.isEmpty {
                Text("None").foregroundStyle(.bizarreOnSurfaceMuted).font(.brandLabelMedium())
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(tags.wrappedValue, id: \.self) { tag in
                            tagChip(tag) {
                                tags.wrappedValue.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }
        }
    }

    private func tagChip(_ tag: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(tag).font(.brandLabelMedium()).foregroundStyle(.bizarreOnSurface)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.system(size: 14))
            }
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(Color.bizarreSurface2, in: Capsule())
    }

    // MARK: - Tag tree node (drill-down, §5.4)

    private func tagNodeRow(_ node: CustomerTagNode, binding: Binding<[String]>) -> AnyView {
        AnyView(tagNodeRowImpl(node, binding: binding))
    }

    @ViewBuilder
    private func tagNodeRowImpl(_ node: CustomerTagNode, binding: Binding<[String]>) -> some View {
        let isSelected = binding.wrappedValue.contains(node.id)
        let hasChildren = !node.children.isEmpty
        let isExpanded = vm.expandedNodes.contains(node.id)

        HStack {
            // Indent by depth
            if node.depth > 0 {
                Spacer().frame(width: CGFloat(node.depth) * 16)
            }

            Button {
                if hasChildren {
                    if isExpanded {
                        vm.expandedNodes.remove(node.id)
                    } else {
                        vm.expandedNodes.insert(node.id)
                    }
                } else {
                    if isSelected {
                        binding.wrappedValue.removeAll { $0 == node.id }
                    } else {
                        binding.wrappedValue.append(node.id)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(node.label)
                        .font(.brandLabelMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if hasChildren {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                    }
                    Spacer()
                    if hasChildren {
                        Text("\(node.children.count)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .accessibilityLabel("\(node.displayPath)\(isSelected ? ", selected" : "")")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
        .buttonStyle(.plain)

        if hasChildren && isExpanded {
            ForEach(node.children, id: \.id) { child in
                tagNodeRow(child, binding: binding)
            }
        }
    }
}
#endif
