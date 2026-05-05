package com.bizarreelectronics.crm.util

/**
 * Per-app language picker — ActionPlan §27.
 *
 * Android 13+ (API 33): delegates to [android.app.LocaleManager.setApplicationLocales]
 * so the OS stores the selection durably and the system Languages screen reflects it.
 *
 * Android 12 and below (API 26-32): the API is unavailable, so we persist the
 * tag in [AppPreferences] only. MainActivity (or the Application) must apply the
 * locale at startup via [applyToContext] before inflation. Because the OS does not
 * know about the override, the selection survives process restarts only while
 * [AppPreferences.languageTag] is read and re-applied at each cold start.
 *
 * The [currentLanguage] StateFlow is the source of truth for the Settings UI;
 * LanguageScreen observes it to show the active selection without peeking at
 * OS internals.
 *
 * Immutability note: [availableLanguages] is a fixed list created once at
 * construction time; [setLanguage] never mutates it.
 */

import android.app.LocaleManager
import android.content.Context
import android.os.Build
import android.os.LocaleList
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LanguageManager @Inject constructor(
    @ApplicationContext private val applicationContext: Context,
    private val appPreferences: AppPreferences,
) {
    /**
     * A language entry displayed in [LanguageScreen].
     * [tag] is a BCP-47 language tag or "system" for the device default.
     * [displayName] is the human-readable label shown in the picker.
     */
    data class Language(val tag: String, val displayName: String)

    /**
     * Ordered list of languages offered in the picker. Immutable.
     *
     * Phase-1 (§27.2): en, es, fr — scaffold translations present (values-es/, values-fr/).
     * Phase-2 (§27.2): pt-BR, de, hi — stubs present; strings fall back to English until
     * a translator populates the values-pt-rBR/, values-de/, values-hi/ files.
     *
     * displayName is shown in the *native* script of the language (per Android i18n convention)
     * so users can identify their language even before switching.
     */
    val availableLanguages: List<Language> = listOf(
        Language("system", "System default"),
        Language("en",     "English"),
        // Phase-1 — scaffold translations present
        Language("es",     "Español"),
        Language("fr",     "Français"),
        // Phase-2 stubs — untranslated; picker shows them so early adopters can test
        Language("pt-BR",  "Português (Brasil)"),
        Language("de",     "Deutsch"),
        Language("hi",     "हिन्दी"),
    )

    private val _currentLanguage = MutableStateFlow(appPreferences.languageTag)

    /** Currently active language tag — "system" or a BCP-47 tag. Observed by the Settings UI. */
    val currentLanguage: StateFlow<String> = _currentLanguage.asStateFlow()

    /**
     * Persist and apply [tag] as the per-app language.
     *
     * On API 33+ the change is handed to [LocaleManager]; the OS delivers an
     * activity recreate automatically so the new locale is applied immediately.
     *
     * On API 26-32 we write the tag to [AppPreferences] and return. The caller
     * (LanguageScreen) is responsible for recreating the activity so the manual
     * Configuration override in [applyToContext] takes effect.
     */
    fun setLanguage(tag: String) {
        appPreferences.languageTag = tag
        _currentLanguage.value = tag

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val localeManager = applicationContext.getSystemService(LocaleManager::class.java)
            val localeList = if (tag == "system") {
                LocaleList.getEmptyLocaleList()
            } else {
                LocaleList.forLanguageTags(tag)
            }
            localeManager.applicationLocales = localeList
        }
        // On API < 33 the locale change takes effect only after the activity
        // recreates and calls applyToContext() in attachBaseContext/onConfigurationChanged.
    }

    /**
     * Returns the display name for [tag], or "Unknown" if the tag is not in
     * [availableLanguages].
     */
    fun displayNameForTag(tag: String): String =
        availableLanguages.firstOrNull { it.tag == tag }?.displayName ?: "Unknown"

    /**
     * Wraps [context] with the persisted language override for API 26-32.
     * Called from MainActivity.attachBaseContext so every view inflation and
     * string lookup uses the user-selected locale even after a cold start.
     *
     * On API 33+ the OS handles locale application via [LocaleManager] and this
     * method is a no-op — the system-provided context already carries the right
     * locale configuration.
     *
     * Usage in MainActivity:
     * ```kotlin
     * override fun attachBaseContext(newBase: Context) {
     *     super.attachBaseContext(LanguageManager.wrapContext(newBase, appPreferences.languageTag))
     * }
     * ```
     *
     * Static form so it can be called before DI is wired (attachBaseContext fires
     * before Hilt components are created for the activity).
     */
    companion object {
        /**
         * Two-arg form: apply a known [tag] to [context]. Used internally and
         * by tests that supply the tag directly.
         */
        fun wrapContext(context: Context, tag: String): Context {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return context
            if (tag == "system" || tag.isBlank()) return context

            val locale = java.util.Locale.forLanguageTag(tag)
            val config = android.content.res.Configuration(context.resources.configuration)
            config.setLocale(locale)
            return context.createConfigurationContext(config)
        }

        /**
         * Single-arg form for use in [MainActivity.attachBaseContext], which
         * fires before the Hilt component graph is ready so constructor
         * injection is unavailable. Reads the persisted language tag directly
         * from the plain [android.content.SharedPreferences] file that
         * [AppPreferences] writes to ("app_prefs" / "language_tag").
         *
         * Fails safe: if the preferences file is absent, the key is missing,
         * or any other error occurs, the original [base] context is returned
         * unchanged so the activity continues with the system locale.
         */
        fun wrapContext(base: Context): Context {
            return try {
                val tag = base
                    .getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
                    .getString("language_tag", "system") ?: "system"
                wrapContext(base, tag)
            } catch (_: Exception) {
                base
            }
        }
    }
}
