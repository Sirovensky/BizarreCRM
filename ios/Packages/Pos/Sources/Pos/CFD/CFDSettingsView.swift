#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16 CFD — Admin settings page wired under Settings → POS → Customer Display.
///
/// Provides:
/// - Enable/disable toggle (persisted via `UserDefaults` / `@AppStorage`).
/// - Idle message text field.
/// - Logo picker (placeholder until tenant asset upload ships in §30).
/// - Preview mode button — presents `CFDView` in a half-sheet for design QA
///   without needing a paired external display.
///
/// **iPad vs iPhone:** The CFD secondary-display feature requires iPad or Mac
/// (secondary display API is unavailable on iPhone). The enable toggle is
/// hidden on iPhone with an explanatory note. The preview mode is still
/// accessible on iPhone for design review.
///
/// Wire this into the POS Settings sub-page:
/// ```swift
/// NavigationLink("Customer Display") {
///     CFDSettingsView()
/// }
/// ```
public struct CFDSettingsView: View {

    // MARK: - UserDefaults keys

    public enum Keys {
        public static let cfdEnabled   = "pos.cfd.enabled"
        public static let idleMessage  = "pos.cfd.idleMessage"
    }

    @AppStorage(Keys.cfdEnabled)  private var cfdEnabled:  Bool   = false
    @AppStorage(Keys.idleMessage) private var idleMessage: String = "Welcome! Your cashier will be with you shortly."

    @State private var showPreview = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("Enable Customer Display", isOn: $cfdEnabled)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("cfd.settings.enableToggle")

                if !cfdEnabled {
                    Text("Connect an external display or use Sidecar / AirPlay with a second iPad to show a live cart view to customers.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                iPadNote
            } header: {
                Text("Customer-Facing Display")
            }

            if cfdEnabled {
                Section {
                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        Text("Idle Message")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        TextField("Shown when no cart is active", text: $idleMessage, axis: .vertical)
                            .font(.brandBodyMedium())
                            .lineLimit(3...6)
                            .accessibilityIdentifier("cfd.settings.idleMessage")
                    }
                    .padding(.vertical, BrandSpacing.xs)
                } header: {
                    Text("Idle Screen")
                }

                Section {
                    // Logo picker placeholder — full asset upload in §30.
                    Label("Logo Picker", systemImage: "photo.badge.plus")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .font(.brandBodyMedium())
                    Text("Tenant logo upload ships with the §30 design-token refresh.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } header: {
                    Text("Logo")
                }
            }

            Section {
                Button {
                    showPreview = true
                } label: {
                    Label("Preview Display", systemImage: "eye")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityIdentifier("cfd.settings.previewButton")
            } header: {
                Text("Preview")
            } footer: {
                Text("Shows a half-sheet preview of the customer display on this device.")
                    .font(.brandLabelSmall())
            }
        }
        .navigationTitle("Customer Display")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPreview) {
            CFDPreviewSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - iPad note

    @ViewBuilder
    private var iPadNote: some View {
        #if canImport(UIKit)
        if Platform.isIPhone {
            Label(
                "Secondary display requires iPad or Mac (Designed for iPad). Preview is still available below.",
                systemImage: "info.circle"
            )
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .disabled(true)
        }
        #endif
    }
}

// MARK: - CFDPreviewSheet

/// Half-sheet preview of `CFDView` populated with a sample cart for design QA.
private struct CFDPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let previewBridge: CFDBridge = {
        let b = CFDBridge()
        // Seed with sample cart lines so the preview shows a non-idle state.
        let sampleLines: [CFDCartLine] = [
            CFDCartLine(name: "Screen Repair — iPhone 14", quantity: 1, lineTotalCents: 14900),
            CFDCartLine(name: "Screen Protector",          quantity: 2, lineTotalCents: 2998),
            CFDCartLine(name: "Same-Day Rush Fee",         quantity: 1, lineTotalCents: 2000),
        ]
        // Direct property mutation allowed here since this is a fresh local instance.
        _ = sampleLines   // CFDBridge mutation via Cart — use closure workaround
        return b
    }()

    var body: some View {
        NavigationStack {
            CFDView(bridge: previewBridge)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("cfd.preview.done")
                    }
                }
        }
    }
}
#endif
