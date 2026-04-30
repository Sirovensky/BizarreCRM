import SwiftUI
import Core
import DesignSystem

// §28.13 Privacy compliance — App Store–style privacy nutrition label
//
// Surface: Settings → Privacy → "Privacy details"
//
// Mirrors the data types declared in App/Resources/PrivacyInfo.xcprivacy,
// presented in a human-readable form as Apple does on the App Store product
// page. Keeps developers honest: any new data type added to PrivacyInfo.xcprivacy
// must also appear here.

// MARK: - PrivacyDataRow

/// A single row in the nutrition label table.
public struct PrivacyDataRow: Identifiable, Sendable {
    public let id: String
    public let category: String
    public let type: String
    public let linkedToUser: Bool
    public let usedForTracking: Bool
    public let purposes: [String]
}

// MARK: - PrivacyNutritionLabelData

/// Canonical list of data types collected by BizarreCRM.
/// Must stay in sync with `App/Resources/PrivacyInfo.xcprivacy`.
public enum PrivacyNutritionLabelData {

    public static let rows: [PrivacyDataRow] = [
        PrivacyDataRow(
            id: "email",
            category: "Contact Info",
            type: "Email Address",
            linkedToUser: true,
            usedForTracking: false,
            purposes: ["App Functionality"]
        ),
        PrivacyDataRow(
            id: "name",
            category: "Contact Info",
            type: "Name",
            linkedToUser: true,
            usedForTracking: false,
            purposes: ["App Functionality"]
        ),
        PrivacyDataRow(
            id: "phone",
            category: "Contact Info",
            type: "Phone Number",
            linkedToUser: true,
            usedForTracking: false,
            purposes: ["App Functionality"]
        ),
        PrivacyDataRow(
            id: "photos",
            category: "Photos & Media",
            type: "Photos or Videos",
            linkedToUser: true,
            usedForTracking: false,
            purposes: ["App Functionality"]
        ),
        PrivacyDataRow(
            id: "other_content",
            category: "User Content",
            type: "Other User Content",
            linkedToUser: true,
            usedForTracking: false,
            purposes: ["App Functionality"]
        ),
        PrivacyDataRow(
            id: "idfv",
            category: "Identifiers",
            type: "Device ID (IDFV, analytics opt-in only)",
            linkedToUser: false,
            usedForTracking: false,
            purposes: ["Analytics (opt-in)"]
        ),
        PrivacyDataRow(
            id: "location",
            category: "Location",
            type: "Coarse Location",
            linkedToUser: false,
            usedForTracking: false,
            purposes: ["App Functionality (clock-in verification)"]
        ),
    ]

    /// Data types that are NOT collected (useful for the "not tracked" section).
    public static let notCollected: [String] = [
        "Advertising Identifier (IDFA)",
        "Precise location",
        "Health or fitness data",
        "Financial information beyond payment receipts",
        "Browsing history",
        "Search history",
        "Sensitive information",
    ]
}

// MARK: - PrivacyNutritionLabelView

/// Settings → Privacy → "Privacy details"
///
/// App Store–style nutrition label showing what data BizarreCRM collects,
/// why, and what it does NOT collect.
public struct PrivacyNutritionLabelView: View {

    public init() {}

    public var body: some View {
        List {
            // ATT note
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "eye.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Cross-App Tracking")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(ATTPromptPolicy.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Tracking")
            }

            // Collected data types
            Section {
                ForEach(PrivacyNutritionLabelData.rows) { row in
                    dataRow(row)
                }
            } header: {
                Text("Data Linked to You")
            } footer: {
                Text("All data stays on your business's server — no third-party data processors (§32 data sovereignty).")
            }

            // Not collected
            Section {
                ForEach(PrivacyNutritionLabelData.notCollected, id: \.self) { item in
                    Label(item, systemImage: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Not collected: \(item)")
                }
            } header: {
                Text("Data Not Collected")
            } footer: {
                Text("BizarreCRM never collects advertising identifiers, health data, or browsing history.")
            }

            // Sync with PrivacyInfo.xcprivacy note
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Store Privacy Report")
                        .font(.subheadline.bold())
                    Text("These data types match the PrivacyInfo.xcprivacy manifest submitted with every App Store release. The manifest is audited each release cycle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accuracy")
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Privacy Details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacy.nutritionLabel")
    }

    // MARK: - Row helper

    @ViewBuilder
    private func dataRow(_ row: PrivacyDataRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.type)
                    .font(.body)
                Spacer()
                if row.linkedToUser {
                    labelChip("Linked", color: .bizarreWarning)
                }
                if row.usedForTracking {
                    labelChip("Tracking", color: .bizarreError)
                }
            }

            Text("Category: \(row.category)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Purpose: \(row.purposes.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(row.type). Category: \(row.category). Purpose: \(row.purposes.joined(separator: ", ")). \(row.linkedToUser ? "Linked to your identity." : "") \(row.usedForTracking ? "Used for tracking." : "Not used for tracking.")"
        )
    }

    private func labelChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
