#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.3 — Chip displayed in `PosCartPanel` when the cart is linked to a
/// repair ticket. Tapping opens a sheet to attach or change the ticket ID.
///
/// The chip shows the linked ticket number when set, or an "unlinked" prompt
/// when nil. The owner of the ticket link state is `Cart.linkedTicketId`.
///
/// Accessibility: combined element with a hint so VoiceOver users understand
/// the purpose without needing to navigate child elements.
@MainActor
public struct PosCartTicketLinkChip: View {

    @Bindable var cart: Cart
    @State private var showSheet: Bool = false
    @State private var inputText: String = ""

    public init(cart: Cart) {
        self.cart = cart
    }

    public var body: some View {
        Button {
            inputText = cart.linkedTicketId.map { String($0) } ?? ""
            showSheet = true
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: cart.linkedTicketId != nil ? "wrench.and.screwdriver.fill" : "link.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityHidden(true)
                Text(chipLabel)
                    .font(.brandLabelLarge())
                    .lineLimit(1)
                if cart.linkedTicketId != nil {
                    Button {
                        cart.unlinkTicket()
                        BrandHaptics.impact(.light)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove ticket link")
                }
            }
            .foregroundStyle(cart.linkedTicketId != nil ? Color.bizarreTeal : Color.bizarreOnSurfaceMuted)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(cart.linkedTicketId != nil
                          ? Color.bizarreTeal.opacity(0.12)
                          : Color.bizarreSurface1.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        cart.linkedTicketId != nil
                            ? Color.bizarreTeal.opacity(0.35)
                            : Color.bizarreOutline.opacity(0.4),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(chipLabel)
        .accessibilityHint("Tap to link or change the repair ticket")
        .accessibilityIdentifier("pos.cart.ticketLinkChip")
        .sheet(isPresented: $showSheet) {
            ticketLinkSheet
        }
    }

    // MARK: - Chip label

    private var chipLabel: String {
        if let id = cart.linkedTicketId {
            return "Ticket #\(id)"
        }
        return "Link to record"
    }

    // MARK: - Sheet

    private var ticketLinkSheet: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                Text("Enter the repair ticket number to associate this sale.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.base)

                HStack(spacing: BrandSpacing.sm) {
                    Text("#")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("1234", text: $inputText)
                        .keyboardType(.numberPad)
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityIdentifier("pos.cart.ticketLink.input")
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, BrandSpacing.base)

                if cart.linkedTicketId != nil {
                    Button(role: .destructive) {
                        cart.unlinkTicket()
                        BrandHaptics.impact(.light)
                        showSheet = false
                    } label: {
                        Label("Remove link", systemImage: "link.badge.minus")
                    }
                    .accessibilityIdentifier("pos.cart.ticketLink.remove")
                }

                Spacer()
            }
            .padding(.top, BrandSpacing.lg)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Link to Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { applyLink() }
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("pos.cart.ticketLink.done")
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func applyLink() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard let id = Int64(trimmed), id > 0 else { return }
        cart.linkToTicket(id: id)
        BrandHaptics.success()
        showSheet = false
    }
}
#endif
