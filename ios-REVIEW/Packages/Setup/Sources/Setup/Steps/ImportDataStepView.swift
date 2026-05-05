import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class ImportDataViewModel {

    // MARK: State

    var selectedSource: ImportSource = .skip

    // MARK: Validation

    var isNextEnabled: Bool {
        Step12Validator.isNextEnabled(source: selectedSource)
    }
}

// MARK: - View  (§36.2 Step 12 — Import Data)

@MainActor
public struct ImportDataStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: (ImportSource) -> Void

    @State private var vm = ImportDataViewModel()

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (ImportSource) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                header
                sourceList
                skipNote
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { onValidityChanged(vm.isNextEnabled) }
        .onChange(of: vm.isNextEnabled) { _, valid in onValidityChanged(valid) }
    }

    // MARK: Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Import Data")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.top, BrandSpacing.lg)
                .accessibilityAddTraits(.isHeader)

            Text("Bring existing customers, tickets, and inventory from another system. You can do this later from Settings → Data Import.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    private var sourceList: some View {
        VStack(spacing: BrandSpacing.sm) {
            ForEach(ImportSource.allCases, id: \.self) { source in
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: ImportSource) -> some View {
        let isSelected = vm.selectedSource == source
        return Button {
            vm.selectedSource = source
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: source.systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                Text(source.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurface)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(
                isSelected ? Color.bizarreOrange.opacity(0.1) : Color.bizarreSurface1.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.bizarreOrange.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.displayName)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var skipNote: some View {
        Group {
            if vm.selectedSource == .skip {
                Text("No data will be imported. You can import later from Settings → Data Import.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .padding(BrandSpacing.md)
                    .background(
                        Color.bizarreSurface1.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: vm.selectedSource)
    }
}
