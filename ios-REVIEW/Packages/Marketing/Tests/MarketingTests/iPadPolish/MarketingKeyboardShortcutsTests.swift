import Testing
import Foundation
@testable import Marketing

// MARK: - MarketingKeyboardShortcutsTests

@Suite("MarketingKeyboardShortcuts")
struct MarketingKeyboardShortcutsTests {

    // MARK: - Shortcut key character values

    @Test("newCampaign key is 'n'")
    func newCampaignKey() {
        #expect(MarketingShortcutRegistry.newCampaign.key == "n")
    }

    @Test("refresh key is 'r'")
    func refreshKey() {
        #expect(MarketingShortcutRegistry.refresh.key == "r")
    }

    @Test("runNow key is carriage return")
    func runNowKey() {
        #expect(MarketingShortcutRegistry.runNow.key == "\r")
    }

    @Test("duplicate key is 'd'")
    func duplicateKey() {
        #expect(MarketingShortcutRegistry.duplicate.key == "d")
    }

    @Test("kindCampaigns key is '1'")
    func kindCampaignsKey() {
        #expect(MarketingShortcutRegistry.kindCampaigns.key == "1")
    }

    @Test("kindCoupons key is '2'")
    func kindCouponsKey() {
        #expect(MarketingShortcutRegistry.kindCoupons.key == "2")
    }

    @Test("kindReferrals key is '3'")
    func kindReferralsKey() {
        #expect(MarketingShortcutRegistry.kindReferrals.key == "3")
    }

    @Test("kindReviews key is '4'")
    func kindReviewsKey() {
        #expect(MarketingShortcutRegistry.kindReviews.key == "4")
    }

    // MARK: - Modifier flags

    @Test("all shortcuts use command modifier", arguments: MarketingShortcutRegistry.all)
    func allUseCommandModifier(descriptor: MarketingShortcutDescriptor) {
        // EventModifierFlags.command = 1_048_576
        #expect(descriptor.modifierFlags == 1_048_576)
    }

    // MARK: - Title non-empty

    @Test("all shortcut titles are non-empty", arguments: MarketingShortcutRegistry.all)
    func allTitlesNonEmpty(descriptor: MarketingShortcutDescriptor) {
        #expect(!descriptor.title.isEmpty)
    }

    // MARK: - Uniqueness

    @Test("all shortcut keys are unique")
    func allKeysUnique() {
        let keys = MarketingShortcutRegistry.all.map { $0.key }
        #expect(Set(keys).count == keys.count)
    }

    @Test("kind shortcut keys are distinct")
    func kindKeysDistinct() {
        let keys = [
            MarketingShortcutRegistry.kindCampaigns.key,
            MarketingShortcutRegistry.kindCoupons.key,
            MarketingShortcutRegistry.kindReferrals.key,
            MarketingShortcutRegistry.kindReviews.key
        ]
        #expect(Set(keys).count == keys.count)
    }

    @Test("primary shortcut keys are distinct")
    func primaryKeysDistinct() {
        let keys = [
            MarketingShortcutRegistry.newCampaign.key,
            MarketingShortcutRegistry.refresh.key,
            MarketingShortcutRegistry.duplicate.key
        ]
        #expect(Set(keys).count == keys.count)
    }

    @Test("registry contains exactly 8 shortcuts")
    func registryCount() {
        #expect(MarketingShortcutRegistry.all.count == 8)
    }

    // MARK: - Modifier callbacks

    @Test("onNewCampaign callback fires")
    func onNewCampaignFires() {
        var fired = false
        let modifier = MarketingKeyboardShortcutsModifier(
            onNewCampaign: { fired = true },
            onRefresh:     {},
            onRunNow:      {},
            onDuplicate:   {},
            onKindChange:  { _ in }
        )
        modifier.onNewCampaign()
        #expect(fired)
    }

    @Test("onRefresh callback fires")
    func onRefreshFires() {
        var fired = false
        let modifier = MarketingKeyboardShortcutsModifier(
            onNewCampaign: {},
            onRefresh:     { fired = true },
            onRunNow:      {},
            onDuplicate:   {},
            onKindChange:  { _ in }
        )
        modifier.onRefresh()
        #expect(fired)
    }

    @Test("onRunNow callback fires")
    func onRunNowFires() {
        var fired = false
        let modifier = MarketingKeyboardShortcutsModifier(
            onNewCampaign: {},
            onRefresh:     {},
            onRunNow:      { fired = true },
            onDuplicate:   {},
            onKindChange:  { _ in }
        )
        modifier.onRunNow()
        #expect(fired)
    }

    @Test("onDuplicate callback fires")
    func onDuplicateFires() {
        var fired = false
        let modifier = MarketingKeyboardShortcutsModifier(
            onNewCampaign: {},
            onRefresh:     {},
            onRunNow:      {},
            onDuplicate:   { fired = true },
            onKindChange:  { _ in }
        )
        modifier.onDuplicate()
        #expect(fired)
    }

    @Test("onKindChange fires for all variants", arguments: MarketingKind.allCases)
    func onKindChangeAllVariants(kind: MarketingKind) {
        var received: MarketingKind?
        let modifier = MarketingKeyboardShortcutsModifier(
            onNewCampaign: {},
            onRefresh:     {},
            onRunNow:      {},
            onDuplicate:   {},
            onKindChange:  { received = $0 }
        )
        modifier.onKindChange(kind)
        #expect(received == kind)
    }

    @Test("onKindChange fires with referrals")
    func onKindChangeReferrals() {
        var received: MarketingKind?
        let modifier = MarketingKeyboardShortcutsModifier(
            onNewCampaign: {},
            onRefresh:     {},
            onRunNow:      {},
            onDuplicate:   {},
            onKindChange:  { received = $0 }
        )
        modifier.onKindChange(.referrals)
        #expect(received == .referrals)
    }
}

