import SwiftUI
import DesignSystem
import Networking

// MARK: - NPSSurveyViewModel

@Observable
@MainActor
public final class NPSSurveyViewModel {
    /// -1 means unset (no selection yet).
    public var score: Int = -1
    public var selectedThemes: Set<String> = []
    public var freeText: String = ""
    public var isSubmitting = false
    public var errorMessage: String?
    public var didSubmit = false

    let customerId: String
    private let api: APIClient

    /// Available theme chips.
    public let themeChips: [String] = [
        "Quality", "Price", "Speed", "Staff", "Cleanliness",
        "Communication", "Scheduling", "Value", "Expertise", "Warranty"
    ]

    public init(customerId: String, api: APIClient) {
        self.customerId = customerId
        self.api = api
    }

    public var canSubmit: Bool { (0...10).contains(score) }

    public var npsCategory: NPSCategory {
        NPSCategory(score: score)
    }

    public func toggleTheme(_ theme: String) {
        if selectedThemes.contains(theme) {
            selectedThemes.remove(theme)
        } else {
            selectedThemes.insert(theme)
        }
    }

    public func submit() async {
        guard canSubmit else {
            errorMessage = "Please select a score from 0 to 10."
            return
        }
        isSubmitting = true
        errorMessage = nil
        let body = NPSSubmitRequest(
            customerId: customerId,
            score: score,
            themes: Array(selectedThemes).sorted(),
            comment: freeText
        )
        do {
            _ = try await api.post("surveys/nps", body: body, as: SurveySubmitResponse.self)
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - NPSSurveyView

/// 0-10 score + optional theme chips + free-text. Submit: POST /surveys/nps.
public struct NPSSurveyView: View {
    @State private var vm: NPSSurveyViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(customerId: String, api: APIClient) {
        _vm = State(initialValue: NPSSurveyViewModel(customerId: customerId, api: api))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                    headerSection
                    scoreSection
                    if vm.score >= 0 {
                        themeSection
                        freeTextSection
                    }
                    submitSection
                }
                .padding(BrandSpacing.base)
            }
            .navigationTitle("How Likely to Recommend?")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .onChange(of: vm.didSubmit) { _, submitted in
                if submitted { dismiss() }
            }
        }
        .presentationDetents([.large])
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("How likely are you to recommend us to a friend or colleague?")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            HStack {
                Text("0 = Not at all")
                Spacer()
                Text("10 = Extremely likely")
            }
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Score selector (0-10 grid)

    private var scoreSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            scoreGrid
            if vm.score >= 0 {
                categoryLabel
            }
        }
    }

    private var scoreGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: BrandSpacing.xs), count: 6),
            spacing: BrandSpacing.xs
        ) {
            ForEach(0...10, id: \.self) { n in
                scoreButton(n)
            }
        }
        .accessibilityLabel("NPS score selector, 0 to 10")
    }

    private func scoreButton(_ n: Int) -> some View {
        let isSelected = vm.score == n
        return Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7)) {
                vm.score = n
            }
        } label: {
            Text("\(n)")
                .font(.brandTitleSmall())
                .frame(maxWidth: .infinity)
                .frame(height: DesignTokens.Touch.minTargetSide)
                .foregroundStyle(isSelected ? Color.bizarreOnOrange : Color.bizarreOnSurface)
        }
        .background(
            isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
        )
        .accessibilityLabel("Score \(n)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var categoryLabel: some View {
        HStack {
            Image(systemName: categoryIcon)
                .foregroundStyle(categoryColor)
                .accessibilityHidden(true)
            Text(categoryText)
                .font(.brandBodyMedium())
                .foregroundStyle(categoryColor)
        }
        .accessibilityLabel(categoryText)
        .transition(.opacity)
    }

    private var categoryIcon: String {
        switch vm.npsCategory {
        case .promoter:  return "face.smiling"
        case .passive:   return "face.dashed"
        case .detractor: return "face.smiling.inverse"
        }
    }

    private var categoryColor: Color {
        switch vm.npsCategory {
        case .promoter:  return .bizarreSuccess
        case .passive:   return .bizarreWarning
        case .detractor: return .bizarreError
        }
    }

    private var categoryText: String {
        switch vm.npsCategory {
        case .promoter:  return "Promoter — thank you!"
        case .passive:   return "Passive — we'd love to improve"
        case .detractor: return "Detractor — we're sorry to hear that"
        }
    }

    // MARK: - Theme chips

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("What drove your score? (optional)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            AnyLayout(WrapLayout(spacing: BrandSpacing.xs)) {
                ForEach(vm.themeChips, id: \.self) { chip in
                    themeChip(chip)
                }
            }
        }
    }

    private func themeChip(_ chip: String) -> some View {
        let isSelected = vm.selectedThemes.contains(chip)
        return Button {
            withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                vm.toggleTheme(chip)
            }
        } label: {
            Text(chip)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .foregroundStyle(isSelected ? Color.bizarreOnOrange : Color.bizarreOnSurface)
        }
        .background(
            isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
            in: Capsule()
        )
        .accessibilityLabel("\(chip)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Free text

    private var freeTextSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Tell us more (optional)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            TextEditor(text: $vm.freeText)
                .font(.brandBodyMedium())
                .frame(minHeight: 80)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityLabel("Additional feedback text field")
        }
    }

    // MARK: - Submit

    private var submitSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Error: \(err)")
            }

            Button {
                Task { await vm.submit() }
            } label: {
                if vm.isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Submit Feedback")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(!vm.canSubmit || vm.isSubmitting)
            .accessibilityLabel(vm.isSubmitting ? "Submitting feedback" : "Submit NPS feedback")
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

// MARK: - WrapLayout

private struct WrapLayout: Layout {
    var spacing: CGFloat = BrandSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowHeight: CGFloat = 0
        var currentX: CGFloat = 0
        var totalHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if index == 0 {
                rowHeight = size.height
                currentX = size.width + spacing
            } else if currentX + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowHeight = size.height
                currentX = size.width + spacing
            } else {
                rowHeight = max(rowHeight, size.height)
                currentX += size.width + spacing
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: max(totalHeight, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
