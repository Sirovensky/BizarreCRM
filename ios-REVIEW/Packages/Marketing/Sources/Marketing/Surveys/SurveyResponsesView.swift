import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §37.3 Survey response tracking — GET /surveys/responses

// MARK: Model

/// A single survey response row.
public struct SurveyResponse: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// "csat" | "nps"
    public let kind: String
    public let customerId: Int64?
    public let customerName: String?
    public let score: Int
    public let comment: String?
    public let submittedAt: String?

    public init(id: Int64, kind: String, customerId: Int64? = nil, customerName: String? = nil,
                score: Int, comment: String? = nil, submittedAt: String? = nil) {
        self.id = id
        self.kind = kind
        self.customerId = customerId
        self.customerName = customerName
        self.score = score
        self.comment = comment
        self.submittedAt = submittedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, score, comment
        case customerId    = "customer_id"
        case customerName  = "customer_name"
        case submittedAt   = "submitted_at"
    }
}

// MARK: - Networking extension (lives here; appended to APIClient+Marketing)

extension APIClient {
    /// `GET /api/v1/surveys/responses` — paginated survey response list.
    public func surveyResponses(kind: String? = nil, pageSize: Int = 50) async throws -> [SurveyResponse] {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let k = kind { items.append(URLQueryItem(name: "kind", value: k)) }
        return try await get("/api/v1/surveys/responses", query: items, as: [SurveyResponse].self)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class SurveyResponsesViewModel {
    public private(set) var responses: [SurveyResponse] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    public var selectedKind: String? = nil   // nil = all

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        if responses.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do { responses = try await api.surveyResponses(kind: selectedKind) }
        catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - View

#if canImport(UIKit)

public struct SurveyResponsesView: View {
    @State private var vm: SurveyResponsesViewModel
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: SurveyResponsesViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: iPhone

    private var compactLayout: some View {
        NavigationStack {
            content
                .navigationTitle("Survey Responses")
                .toolbar { kindPickerToolbar }
        }
    }

    // MARK: iPad

    private var regularLayout: some View {
        NavigationSplitView {
            content
                .navigationTitle("Survey Responses")
                .toolbar { kindPickerToolbar }
                .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 560)
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "star.bubble").font(.system(size: 36)).foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
                    Text("Select a response").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Kind picker toolbar

    private var kindPickerToolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button { vm.selectedKind = nil; Task { await vm.load() } } label: {
                    Label("All", systemImage: vm.selectedKind == nil ? "checkmark" : "")
                }
                Button { vm.selectedKind = "csat"; Task { await vm.load() } } label: {
                    Label("CSAT", systemImage: vm.selectedKind == "csat" ? "checkmark" : "")
                }
                Button { vm.selectedKind = "nps"; Task { await vm.load() } } label: {
                    Label("NPS", systemImage: vm.selectedKind == "nps" ? "checkmark" : "")
                }
            } label: {
                Label("Kind", systemImage: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter by survey kind")
        }
    }

    // MARK: Shared content

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(.bizarreError).accessibilityHidden(true)
                    Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.responses.isEmpty {
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "star.bubble").font(.system(size: 36)).foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
                    Text("No responses yet.").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.responses) { response in
                    SurveyResponseRow(response: response)
                        .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - Row

private struct SurveyResponseRow: View {
    let response: SurveyResponse

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // Score circle
            ZStack {
                Circle().fill(scoreColor.opacity(0.15))
                Text("\(response.score)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .monospacedDigit()
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    if let name = response.customerName, !name.isEmpty {
                        Text(name)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(response.kind.uppercased())
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.bizarreSurface2, in: Capsule())
                }

                if let comment = response.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                }

                if let date = response.submittedAt {
                    Text(String(date.prefix(10)))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var scoreColor: Color {
        if response.kind == "csat" {
            return response.score >= 4 ? .bizarreSuccess : response.score == 3 ? .bizarreWarning : .bizarreError
        }
        // NPS
        return response.score >= 9 ? .bizarreSuccess : response.score >= 7 ? .bizarreWarning : .bizarreError
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let name = response.customerName { parts.append(name) }
        parts.append("\(response.kind.uppercased()): \(response.score)")
        if let comment = response.comment, !comment.isEmpty { parts.append(comment) }
        return parts.joined(separator: ". ")
    }
}
#endif
