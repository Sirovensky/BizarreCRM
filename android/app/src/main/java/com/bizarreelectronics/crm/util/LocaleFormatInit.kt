package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import javax.inject.Inject
import javax.inject.Singleton

/**
 * LocaleFormatInit — ActionPlan §27.3.
 *
 * Wires per-user format overrides from [AppPreferences] into the formatter
 * singletons ([DateFormatter] and [CurrencyFormatter]) so that:
 *
 *   - [DateFormatter.timezoneOverride] reflects the user's saved timezone choice.
 *   - [CurrencyFormatter.defaultCurrencyCode] reflects the user's saved currency choice.
 *
 * Must be called once at app-start — after Hilt injects [AppPreferences] — so that
 * all subsequent date/currency renders in Composables, ViewModels, and print paths
 * pick up the user's preference without repeating the pref lookup at every call-site.
 *
 * Called from [com.bizarreelectronics.crm.BizarreCrmApp.onCreate] via injection.
 *
 * Thread-safety: both formatter singletons use [@Volatile] fields so concurrent
 * reads from Compose/background threads see consistent values after [init] returns.
 */
@Singleton
class LocaleFormatInit @Inject constructor(
    private val appPreferences: AppPreferences,
) {
    /**
     * Apply the saved timezone and currency overrides to the formatter singletons.
     * Idempotent — safe to call multiple times (e.g. after a settings change).
     */
    fun init() {
        DateFormatter.timezoneOverride = appPreferences.timezoneOverride
        CurrencyFormatter.defaultCurrencyCode = appPreferences.currencyOverride
    }

    /**
     * Re-apply after the user changes their timezone override in [LanguageScreen].
     * Called by [LanguageViewModel.setTimezoneOverride] so existing rendered
     * dates on visible screens pick up the new zone on next recomposition.
     */
    fun onTimezoneChanged(zoneId: String?) {
        DateFormatter.timezoneOverride = zoneId
    }

    /**
     * Re-apply after the user changes their currency override in [LanguageScreen].
     * Called by [LanguageViewModel.setCurrencyOverride] so price displays on
     * visible screens reflect the new currency on next recomposition.
     */
    fun onCurrencyChanged(currencyCode: String?) {
        CurrencyFormatter.defaultCurrencyCode = currencyCode
    }
}
