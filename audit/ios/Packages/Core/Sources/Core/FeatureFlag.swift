import Foundation

/// All known server-side feature flags.
///
/// Rules (per `ios/agent-ownership.md` shared additive zone):
/// - Add new cases at the bottom — never reorder or remove existing ones.
/// - Default values should be conservative (usually `false` = off).
/// - Each flag maps to the string returned by the `/feature-flags` endpoint.
public enum FeatureFlag: String, CaseIterable, Sendable {
    // MARK: - Core product flags
    case newDashboardLayout         = "new_dashboard_layout"
    case kioskMode                  = "kiosk_mode"
    case trainingMode               = "training_mode"
    case setupWizard                = "setup_wizard"
    case priceOverrides             = "price_overrides"

    // MARK: - POS flags
    case paymentLinks               = "payment_links"
    case giftCards                  = "gift_cards"
    case splitPayments              = "split_payments"
    case cashDrawer                 = "cash_drawer"

    // MARK: - Customer / loyalty
    case loyaltyProgram             = "loyalty_program"
    case referralTracking           = "referral_tracking"
    case reviewSolicitation         = "review_solicitation"
    case memberships                = "memberships"

    // MARK: - Communication
    case smsMarketing               = "sms_marketing"
    case emailCampaigns             = "email_campaigns"
    case surveyCollection           = "survey_collection"

    // MARK: - Hardware
    case blockchypTerminal          = "blockchyp_terminal"
    case labelPrinting              = "label_printing"
    case weightScale                = "weight_scale"

    // MARK: - Platform
    case widgetShortcuts            = "widget_shortcuts"
    case spotlightIndexing          = "spotlight_indexing"
    case siriIntents                = "siri_intents"
    case handoffContinuity          = "handoff_continuity"

    // MARK: - Admin / dev
    case featureFlagOverrides       = "feature_flag_overrides"
    case debugDrawer                = "debug_drawer"
    case dataImport                 = "data_import"
    case dataExport                 = "data_export"

    // MARK: Defaults

    /// Conservative default when neither server nor local override is set.
    public var defaultValue: Bool {
        switch self {
        case .newDashboardLayout:   return false
        case .kioskMode:            return false
        case .trainingMode:         return false
        case .setupWizard:          return true
        case .priceOverrides:       return false
        case .paymentLinks:         return true
        case .giftCards:            return true
        case .splitPayments:        return false
        case .cashDrawer:           return true
        case .loyaltyProgram:       return false
        case .referralTracking:     return false
        case .reviewSolicitation:   return false
        case .memberships:          return false
        case .smsMarketing:         return false
        case .emailCampaigns:       return false
        case .surveyCollection:     return false
        case .blockchypTerminal:    return false
        case .labelPrinting:        return false
        case .weightScale:          return false
        case .widgetShortcuts:      return true
        case .spotlightIndexing:    return true
        case .siriIntents:          return true
        case .handoffContinuity:    return true
        case .featureFlagOverrides: return false
        case .debugDrawer:          return false
        case .dataImport:           return false
        case .dataExport:           return true
        }
    }

    /// Human-readable display name for admin UI.
    public var displayName: String {
        switch self {
        case .newDashboardLayout:   return "New Dashboard Layout"
        case .kioskMode:            return "Kiosk Mode"
        case .trainingMode:         return "Training Mode"
        case .setupWizard:          return "Setup Wizard"
        case .priceOverrides:       return "Price Overrides"
        case .paymentLinks:         return "Payment Links"
        case .giftCards:            return "Gift Cards"
        case .splitPayments:        return "Split Payments"
        case .cashDrawer:           return "Cash Drawer"
        case .loyaltyProgram:       return "Loyalty Program"
        case .referralTracking:     return "Referral Tracking"
        case .reviewSolicitation:   return "Review Solicitation"
        case .memberships:          return "Memberships"
        case .smsMarketing:         return "SMS Marketing"
        case .emailCampaigns:       return "Email Campaigns"
        case .surveyCollection:     return "Survey Collection"
        case .blockchypTerminal:    return "BlockChyp Terminal"
        case .labelPrinting:        return "Label Printing"
        case .weightScale:          return "Weight Scale"
        case .widgetShortcuts:      return "Widget Shortcuts"
        case .spotlightIndexing:    return "Spotlight Indexing"
        case .siriIntents:          return "Siri Intents"
        case .handoffContinuity:    return "Handoff / Continuity"
        case .featureFlagOverrides: return "Feature Flag Overrides"
        case .debugDrawer:          return "Debug Drawer"
        case .dataImport:           return "Data Import"
        case .dataExport:           return "Data Export"
        }
    }
}
