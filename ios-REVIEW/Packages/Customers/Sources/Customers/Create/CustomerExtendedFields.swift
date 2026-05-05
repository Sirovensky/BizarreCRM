#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - §5.3 Extended customer create fields
// type (person/business), birthday, tags chip picker, communication prefs,
// referral source — added to CustomerCreateViewModel and CustomerFormView.

/// Communication preference opt-in flags.
public struct CustomerCommPrefs: Equatable, Sendable {
    public var smsOptIn: Bool = true
    public var emailOptIn: Bool = true
    public var callOptIn: Bool = true
    public var marketingOptIn: Bool = false

    public init() {}
}

/// Extended create / edit fields that go beyond the minimal form.
public struct CustomerExtendedFieldsSection: View {
    @Binding var type: String              // "person" | "business"
    @Binding var birthday: Date?
    @Binding var hasBirthday: Bool
    @Binding var tags: [String]
    @Binding var tagInput: String
    @Binding var referralSource: String
    @Binding var commPrefs: CustomerCommPrefs

    private let referralOptions = ["Walk-in", "Google", "Yelp", "Facebook", "Referral", "Website", "Other"]

    public init(
        type: Binding<String>,
        birthday: Binding<Date?>,
        hasBirthday: Binding<Bool>,
        tags: Binding<[String]>,
        tagInput: Binding<String>,
        referralSource: Binding<String>,
        commPrefs: Binding<CustomerCommPrefs>
    ) {
        _type = type
        _birthday = birthday
        _hasBirthday = hasBirthday
        _tags = tags
        _tagInput = tagInput
        _referralSource = referralSource
        _commPrefs = commPrefs
    }

    public var body: some View {
        Group {
            // Customer type
            Section("Type") {
                Picker("Customer type", selection: $type) {
                    Text("Person").tag("person")
                    Text("Business").tag("business")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Customer type: \(type == "person" ? "Person" : "Business")")
            }

            // Birthday (opt-in)
            Section("Birthday") {
                Toggle("Has birthday on file", isOn: $hasBirthday)
                    .accessibilityLabel("Include birthday")
                if hasBirthday {
                    DatePicker(
                        "Birthday",
                        selection: Binding(
                            get: { birthday ?? Date() },
                            set: { birthday = $0 }
                        ),
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .accessibilityLabel("Customer birthday")
                    .datePickerStyle(.compact)
                }
            }

            // Tags chip picker
            Section("Tags") {
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: BrandSpacing.xs) {
                            ForEach(tags, id: \.self) { tag in
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(tag).font(.brandLabelLarge())
                                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                            .accessibilityHidden(true)
                                    }
                                    .foregroundStyle(.bizarreOnSurface)
                                    .padding(.horizontal, BrandSpacing.sm)
                                    .padding(.vertical, BrandSpacing.xxs)
                                    .background(Color.bizarreSurface2, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove tag \(tag)")
                            }
                        }
                    }
                    .accessibilityLabel("Current tags: \(tags.joined(separator: ", "))")
                }
                HStack(spacing: BrandSpacing.sm) {
                    TextField("Add tag…", text: $tagInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("New tag")
                        .onSubmit { addTag() }
                    if !tagInput.isEmpty {
                        Button { addTag() } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.bizarreOrange)
                                .font(.system(size: 22))
                        }
                        .accessibilityLabel("Add tag \(tagInput)")
                    }
                }
                if tags.count >= 10 {
                    Text("\(tags.count) of 20 tags used.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(tags.count >= 20 ? .bizarreError : .bizarreOnSurfaceMuted)
                        .accessibilityLabel("\(tags.count) of 20 tags")
                }
            }

            // Referral source
            Section("Referral source") {
                Picker("How they found you", selection: $referralSource) {
                    Text("—").tag("")
                    ForEach(referralOptions, id: \.self) { src in
                        Text(src).tag(src)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Referral source: \(referralSource.isEmpty ? "none" : referralSource)")
            }

            // Communication preferences
            Section("Communication preferences") {
                Toggle("SMS / text messages", isOn: $commPrefs.smsOptIn)
                    .accessibilityLabel("Allow SMS messages: \(commPrefs.smsOptIn ? "on" : "off")")
                Toggle("Email", isOn: $commPrefs.emailOptIn)
                    .accessibilityLabel("Allow email: \(commPrefs.emailOptIn ? "on" : "off")")
                Toggle("Phone calls", isOn: $commPrefs.callOptIn)
                    .accessibilityLabel("Allow phone calls: \(commPrefs.callOptIn ? "on" : "off")")
                Toggle("Marketing messages", isOn: $commPrefs.marketingOptIn)
                    .accessibilityLabel("Allow marketing: \(commPrefs.marketingOptIn ? "on" : "off")")
            }
        }
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed), tags.count < 20 else {
            tagInput = ""
            return
        }
        tags.append(trimmed)
        tagInput = ""
    }
}

// MARK: - Extended create request

/// §5.3 extended create payload — wraps the core fields and adds the new ones
/// so the server receives them without modifying the existing `CreateCustomerRequest`.
public struct CreateCustomerExtendedRequest: Encodable, Sendable {
    public let firstName: String
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let mobile: String?
    public let organization: String?
    public let address1: String?
    public let city: String?
    public let state: String?
    public let postcode: String?
    public let notes: String?
    // Extended §5.3 fields
    public let type: String?
    public let birthday: String?
    public let tags: [String]?
    public let referralSource: String?
    public let smsOptIn: Bool?
    public let emailOptIn: Bool?
    public let callOptIn: Bool?
    public let marketingOptIn: Bool?

    public init(
        firstName: String,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        mobile: String? = nil,
        organization: String? = nil,
        address1: String? = nil,
        city: String? = nil,
        state: String? = nil,
        postcode: String? = nil,
        notes: String? = nil,
        type: String? = nil,
        birthday: String? = nil,
        tags: [String]? = nil,
        referralSource: String? = nil,
        smsOptIn: Bool? = nil,
        emailOptIn: Bool? = nil,
        callOptIn: Bool? = nil,
        marketingOptIn: Bool? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.mobile = mobile
        self.organization = organization
        self.address1 = address1
        self.city = city
        self.state = state
        self.postcode = postcode
        self.notes = notes
        self.type = type
        self.birthday = birthday
        self.tags = tags
        self.referralSource = referralSource
        self.smsOptIn = smsOptIn
        self.emailOptIn = emailOptIn
        self.callOptIn = callOptIn
        self.marketingOptIn = marketingOptIn
    }

    enum CodingKeys: String, CodingKey {
        case email, phone, mobile, organization, address1, city, state, postcode, type, birthday, tags
        case firstName      = "first_name"
        case lastName       = "last_name"
        case notes          = "comments"
        case referralSource = "referral_source"
        case smsOptIn       = "sms_opt_in"
        case emailOptIn     = "email_opt_in"
        case callOptIn      = "call_opt_in"
        case marketingOptIn = "marketing_opt_in"
    }
}
#endif
