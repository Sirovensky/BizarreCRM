#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

// §5.6 — Sub-contacts section embedded in CustomerDetailView.

public struct CustomerContactListView: View {
    @State private var vm: CustomerContactViewModel
    @State private var showingAdd: Bool = false
    @State private var editTarget: CustomerContact? = nil

    public init(api: APIClient, customerId: Int64) {
        _vm = State(wrappedValue: CustomerContactViewModel(api: api, customerId: customerId))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Contacts")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                Button {
                    vm.prepareNew()
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add contact")
            }

            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, BrandSpacing.sm)
            } else if vm.contacts.isEmpty {
                Text("No contacts yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(vm.contacts) { contact in
                    contactRow(contact)
                }
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await vm.load() }
        .sheet(isPresented: $showingAdd) {
            CustomerContactEditSheet(vm: vm)
        }
        .sheet(item: $editTarget) { contact in
            CustomerContactEditSheet(vm: vm)
                .onAppear { vm.prepareEdit(contact) }
        }
    }

    private func contactRow(_ c: CustomerContact) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: BrandSpacing.xs) {
                    Text(c.name)
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if c.isPrimary {
                        Text("Primary")
                            .font(.brandLabelSmall())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.bizarreOrange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityLabel("Primary contact")
                    }
                }
                if let rel = c.relationship, !rel.isEmpty {
                    Text(rel)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let phone = c.phone, !phone.isEmpty {
                    Text(PhoneFormatter.format(phone))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                if let email = c.email, !email.isEmpty {
                    Text(email)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
            Spacer(minLength: 0)
            Button {
                editTarget = c
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Edit \(c.name)")
        }
        .padding(.vertical, BrandSpacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await vm.deleteContact(c) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.name)\(c.relationship.map { ", \($0)" } ?? "")")
    }
}
#endif
