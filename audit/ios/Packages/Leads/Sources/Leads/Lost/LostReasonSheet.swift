import SwiftUI
import Networking
import DesignSystem
import Core

// MARK: - LostReason

public enum LostReason: String, CaseIterable, Sendable, Identifiable {
    case price        = "price"
    case timing       = "timing"
    case competitor   = "competitor"
    case noResponse   = "no_response"
    case other        = "other"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .price:      return "Price"
        case .timing:     return "Timing"
        case .competitor: return "Went with competitor"
        case .noResponse: return "No response"
        case .other:      return "Other"
        }
    }
}

// MARK: - LostReasonViewModel

@MainActor
@Observable
final class LostReasonViewModel {

    enum State: Sendable {
        case idle, submitting, success, failed(String)
    }

    var selectedReason: LostReason = .price
    var notes: String = ""
    var state: State = .idle

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let leadId: Int64

    init(api: APIClient, leadId: Int64) {
        self.api = api
        self.leadId = leadId
    }

    func submit() async {
        guard case .idle = state else { return }
        state = .submitting
        do {
            // Server has no /leads/:id/lose route. Lost reason is submitted via
            // PUT /leads/:id with status=lost + lost_reason field
            // (see leads.routes.ts line 770-782).
            let body = LeadUpdateBody(
                status: "lost",
                notes: notes.isEmpty ? nil : notes,
                lostReason: selectedReason.rawValue
            )
            _ = try await api.updateLead(id: leadId, body: body)
            state = .success
        } catch {
            AppLog.ui.error("Lead lose failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - LostReasonSheet

/// §9.5 — Required when marking a lead as Lost.
/// Presents a reason picker + free-text notes field.
public struct LostReasonSheet: View {
    @State private var vm: LostReasonViewModel
    private let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, leadId: Int64, onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
        _vm = State(wrappedValue: LostReasonViewModel(api: api, leadId: leadId))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        reasonPicker
                        notesField
                        submitButton
                        if case .failed(let msg) = vm.state {
                            Text(msg)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreError)
                        }
                    }
                    .padding(BrandSpacing.base)
                    .frame(maxWidth: 600, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Mark as Lost")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(vm.state == .submitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: vm.state == .success) { _, isSuccess in
            if isSuccess {
                onSuccess()
                dismiss()
            }
        }
    }

    // MARK: - Sub-views

    private var reasonPicker: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("REASON")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
            VStack(spacing: 0) {
                ForEach(Array(LostReason.allCases.enumerated()), id: \.element.id) { idx, reason in
                    Button {
                        vm.selectedReason = reason
                    } label: {
                        HStack {
                            Text(reason.displayName)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            if vm.selectedReason == reason {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.bizarreOrange)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, BrandSpacing.sm)
                        .padding(.horizontal, BrandSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                    .accessibilityLabel("\(reason.displayName)\(vm.selectedReason == reason ? ", selected" : "")")
                    if idx < LostReason.allCases.count - 1 {
                        Divider().overlay(Color.bizarreOutline.opacity(0.25))
                    }
                }
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("NOTES (OPTIONAL)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
            TextEditor(text: $vm.notes)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .frame(minHeight: 80)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        }
    }

    private var submitButton: some View {
        Button {
            Task { await vm.submit() }
        } label: {
            Group {
                if vm.state == .submitting {
                    ProgressView().tint(.bizarreOnOrange)
                } else {
                    Text("Mark as Lost")
                        .font(.brandTitleSmall())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreError)
        .disabled(vm.state == .submitting)
    }
}

// MARK: - State Equatable helpers

extension LostReasonViewModel.State: Equatable {
    static func == (lhs: LostReasonViewModel.State, rhs: LostReasonViewModel.State) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.submitting, .submitting), (.success, .success): return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}
