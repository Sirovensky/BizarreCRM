/// CheckInDamageView.swift — §16.25.3
///
/// Step 3: Pre-existing damage diagram, overall condition, accessories, LDI.
/// Canvas damage marker is a simplified tap-to-add implementation (full SVG
/// path rendering deferred; uses Canvas API for normalized coordinate markers).
/// Spec: mockup frame "CI-3 · Damage we're NOT fixing · liability record".

#if canImport(UIKit)
import SwiftUI
import DesignSystem

struct CheckInDamageView: View {
    @Bindable var draft: CheckInDraft
    @State private var selectedFace: DamageMarker.Face = .front
    @State private var pendingMarkerPosition: CGPoint? = nil
    @State private var showMarkerTypePicker: Bool = false

    private let accessories = ["SIM tray", "Case", "Tempered glass", "Charger", "Cable"]

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // Face tabs
                faceTabs

                // Device diagram canvas
                deviceCanvas

                // Condition chips
                conditionRow

                Divider().padding(.horizontal, BrandSpacing.base)

                // Accessories chips
                accessoriesRow

                Divider().padding(.horizontal, BrandSpacing.base)

                // LDI card
                ldiCard
            }
            .padding(.vertical, BrandSpacing.md)
            .padding(.bottom, BrandSpacing.xl)
        }
        .animation(.easeOut(duration: 0.15), value: selectedFace)
    }

    // MARK: - Face tabs

    private var faceTabs: some View {
        Picker("Face", selection: $selectedFace) {
            Text("Front").tag(DamageMarker.Face.front)
            Text("Back").tag(DamageMarker.Face.back)
            Text("Sides").tag(DamageMarker.Face.sides)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Device canvas

    private var deviceCanvas: some View {
        let faceMarkers = draft.damageMarkers.filter { $0.face == selectedFace }

        return GeometryReader { geo in
            ZStack {
                // Phone silhouette background
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.bizarreSurface2)
                    .frame(width: geo.size.width * 0.55, height: geo.size.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 1)
                    )

                // Damage markers
                Canvas { context, size in
                    for marker in faceMarkers {
                        let x = marker.x * size.width
                        let y = marker.y * size.height
                        let color: Color = {
                            switch marker.type {
                            case .crack:   return .bizarreError
                            case .scratch, .dent: return .bizarreWarning
                            case .stain:   return .bizarreOnSurfaceMuted
                            }
                        }()
                        let path = Path(ellipseIn: CGRect(x: x - 8, y: y - 8, width: 16, height: 16))
                        context.fill(path, with: .color(color))
                    }
                }
                .frame(width: geo.size.width * 0.55, height: geo.size.height)
                .accessibilityLabel("Device diagram — tap to mark pre-existing damage")
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let normalized = CGPoint(
                        x: (location.x - geo.size.width * 0.225) / (geo.size.width * 0.55),
                        y: location.y / geo.size.height
                    )
                    guard (0.0...1.0).contains(normalized.x), (0.0...1.0).contains(normalized.y) else { return }
                    let newMarker = DamageMarker(x: normalized.x, y: normalized.y, type: .crack, face: selectedFace)
                    draft.damageMarkers = draft.damageMarkers + [newMarker]
                    BrandHaptics.tap()
                }
            }
        }
        .frame(height: 200)
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Condition row

    private var conditionRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Overall condition")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(OverallCondition.allCases, id: \.self) { cond in
                        Button {
                            BrandHaptics.tap()
                            draft.overallCondition = cond
                        } label: {
                            Text(cond.rawValue.capitalized)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(draft.overallCondition == cond ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(draft.overallCondition == cond ? Color.bizarreOrange : Color.bizarreSurface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }
        }
    }

    // MARK: - Accessories row

    private var accessoriesRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Accessories included")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(accessories, id: \.self) { accessory in
                        let isSelected = draft.accessories.contains(accessory)
                        Button {
                            BrandHaptics.tap()
                            if isSelected {
                                draft.accessories = draft.accessories.filter { $0 != accessory }
                            } else {
                                draft.accessories = draft.accessories + [accessory]
                            }
                        } label: {
                            Text(accessory)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(isSelected ? Color.bizarreOrange : Color.bizarreSurface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }
        }
    }

    // MARK: - LDI card

    private var ldiCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Liquid damage indicator")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)

            HStack(spacing: BrandSpacing.sm) {
                ForEach(LDIStatus.allCases, id: \.self) { status in
                    Button {
                        BrandHaptics.tap()
                        draft.ldiStatus = status
                    } label: {
                        Text(status.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(draft.ldiStatus == status ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.xs)
                            .background(
                                draft.ldiStatus == status
                                    ? (status == .tripped ? Color.bizarreError : Color.bizarreOrange)
                                    : Color.bizarreSurface2,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BrandSpacing.base)

            if draft.ldiStatus == .tripped {
                HStack {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(Color.bizarreError)
                    Text("Photograph LDI indicator")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.bizarreError)
                }
                .padding(BrandSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(Color.bizarreError.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, BrandSpacing.base)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: draft.ldiStatus)
    }
}
#endif
