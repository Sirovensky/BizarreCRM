/// CheckInDiagnosticView.swift — §16.25.4
///
/// Step 4: Pre-repair diagnostic checklist.
/// Tri-state toggle: ✓ (ok) / ✕ (fail) / ? (untested).
/// "All OK" quick-fill bar. Required fields (Touchscreen for cracked-screen tickets).
/// Spec: mockup frame "CI-4 · Pre-repair diagnostic · what works now".

#if canImport(UIKit)
import SwiftUI
import DesignSystem

struct CheckInDiagnosticView: View {
    @Bindable var draft: CheckInDraft

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.md) {
                // "All OK" quick-fill bar
                allOKBar

                // Checklist
                LazyVStack(spacing: 0) {
                    ForEach(draft.diagnosticResults) { item in
                        diagnosticRow(item)
                        Divider().padding(.leading, BrandSpacing.xl + BrandSpacing.md)
                    }
                }
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, BrandSpacing.base)
            }
            .padding(.vertical, BrandSpacing.md)
            .padding(.bottom, BrandSpacing.xl)
        }
    }

    // MARK: - All OK bar

    private var allOKBar: some View {
        HStack {
            Text("Mark all as working?")
                .font(.system(size: 13))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Spacer()
            Button {
                BrandHaptics.tap()
                withAnimation(.easeOut(duration: 0.2)) {
                    draft.setAllDiagnosticOK()
                }
            } label: {
                Label("All OK", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.bizarreSuccess)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.xs)
                    .background(Color.bizarreSuccess.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreTeal.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Diagnostic row

    private func diagnosticRow(_ item: DiagnosticResult) -> some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.bizarreOnSurface)
            }
            Spacer()
            // Tri-state toggle: ✓ / ✕ / ?
            triStateButtons(item: item)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName) — \(item.state.accessibilityLabel)")
    }

    private func triStateButtons(item: DiagnosticResult) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            triButton(item: item, state: .ok,       label: "✓", icon: "checkmark", color: .bizarreSuccess)
            triButton(item: item, state: .fail,     label: "✕", icon: "xmark",     color: .bizarreError)
            triButton(item: item, state: .untested, label: "?", icon: "questionmark", color: .bizarreWarning)
        }
    }

    private func triButton(
        item: DiagnosticResult,
        state: DiagnosticResult.State,
        label: String,
        icon: String,
        color: Color
    ) -> some View {
        let isActive = item.state == state
        return Button {
            BrandHaptics.tap()
            withAnimation(.easeOut(duration: 0.12)) {
                draft.setDiagnosticState(id: item.id, state: state)
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isActive ? Color.white : Color.bizarreOnSurfaceMuted)
                .frame(width: 30, height: 30)
                .background(isActive ? color : Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(isActive ? "selected" : "not selected")
    }
}

extension DiagnosticResult.State {
    var accessibilityLabel: String {
        switch self {
        case .ok: return "OK"
        case .fail: return "Failed"
        case .untested: return "Untested"
        }
    }
}
#endif
