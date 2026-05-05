package com.bizarreelectronics.crm.util

/**
 * Maps [AppError] instances to human-readable [Recovery] objects that feature
 * modules consume when rendering error composables (plan §1 L226-L230).
 *
 * Taxonomy (plan §1 L226):
 *  - [AppError.Network]     → offline / unreachable; suggest retry + enable network
 *  - [AppError.Server]      → HTTP 4xx/5xx variants with tailored copy
 *  - [AppError.Auth]        → session / permission variants leading to re-login or settings
 *  - [AppError.Validation]  → field-level errors rendered as a bullet list
 *  - [AppError.NotFound]    → entity-specific "not found" copy
 *  - [AppError.Conflict]    → concurrent-edit conflict
 *  - [AppError.Storage]     → disk-full or storage-permission issues
 *  - [AppError.Hardware]    → camera / scanner / printer / terminal failures
 *  - [AppError.Cancelled]   → user-initiated cancel; UI should stay silent
 *  - [AppError.Unknown]     → catch-all with contact-support
 *
 * The [Action] enum in plan §1 L227 defines the `suggestedActions` contract;
 * feature modules decide how to render each action (button, link, banner).
 *
 * Error-recovery UI per taxonomy case lives in each feature module (plan §1 L230).
 * This object is pure data — no Context, no Compose imports.
 */
object ErrorRecovery {

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Actions a feature module's error composable can offer the user.
     * (plan §1 L227 — suggestedActions contract)
     *
     * i18n: action labels are wired via feature-module composables; this enum
     * carries semantic identity only.
     */
    enum class Action {
        /** Re-issue the failed request. */
        Retry,

        /** Open Android Wi-Fi / mobile-data settings. */
        EnableNetwork,

        /** Navigate to the login screen and clear the session. */
        ReLogin,

        /** Open the relevant Android system settings panel. */
        OpenSettings,

        /** Open the in-app contact-support flow or email. */
        ContactSupport,

        /** Close the error surface without taking further action. */
        Dismiss,

        /** Open Android storage settings or prompt the user to free space. */
        FreeStorage,

        /** Advance the device clock / open date-time settings (NTP drift). */
        AdjustTime,
    }

    /**
     * Human-readable recovery information for one [AppError] instance.
     *
     * @param title         Short headline shown in dialogs / banners.
     *                      Always non-blank unless [AppError.Cancelled].
     * @param message       Longer explanation. May be empty for [AppError.Cancelled].
     * @param actions       Ordered list of actions the UI should offer.
     * @param destructive   When `true` the primary action is irreversible
     *                      (e.g. forced sign-out after session revocation).
     */
    data class Recovery(
        val title: String,
        val message: String,
        val actions: List<Action>,
        val destructive: Boolean = false,
    )

    /**
     * Derive a [Recovery] from any [AppError].
     *
     * @param error               The error to map.
     * @param fieldErrorsAsBullets When `true` (default) [AppError.Validation] errors are
     *                             rendered as a `• field: message` bullet list.
     *                             When `false` only the first field's message is used.
     */
    fun recover(error: AppError, fieldErrorsAsBullets: Boolean = true): Recovery = when (error) {

        // -----------------------------------------------------------------
        // Network — device offline, DNS failure, socket timeout
        // -----------------------------------------------------------------
        is AppError.Network -> Recovery(
            title = "Can't reach server", // TODO(i18n)
            message = "Check your connection and try again.", // TODO(i18n)
            actions = listOf(Action.Retry, Action.EnableNetwork),
        )

        // -----------------------------------------------------------------
        // Server — differentiated by HTTP status code
        // -----------------------------------------------------------------
        is AppError.Server -> serverRecovery(error)

        // -----------------------------------------------------------------
        // Auth — session/permission variants
        // -----------------------------------------------------------------
        is AppError.Auth -> authRecovery(error)

        // -----------------------------------------------------------------
        // Validation — one or more field errors from 422
        // -----------------------------------------------------------------
        is AppError.Validation -> Recovery(
            title = "Check your inputs", // TODO(i18n)
            message = validationMessage(error.errors, fieldErrorsAsBullets),
            actions = listOf(Action.Dismiss),
        )

        // -----------------------------------------------------------------
        // NotFound — referenced entity was deleted or never existed
        // -----------------------------------------------------------------
        is AppError.NotFound -> Recovery(
            title = "${capitalize(error.entity)} not found", // TODO(i18n)
            message = "That ${error.entity.lowercase()} may have been deleted or you don't have access.", // TODO(i18n)
            actions = listOf(Action.Dismiss),
        )

        // -----------------------------------------------------------------
        // Conflict — concurrent edit detected (409 / explicit branch)
        // -----------------------------------------------------------------
        is AppError.Conflict -> Recovery(
            title = "Conflict detected", // TODO(i18n)
            message = buildString { // TODO(i18n)
                append("Someone else made changes at the same time.")
                if (!error.serverUpdatedAt.isNullOrBlank()) {
                    append(" Last updated: ${error.serverUpdatedAt}.")
                }
            },
            actions = listOf(Action.Retry, Action.Dismiss),
        )

        // -----------------------------------------------------------------
        // Storage — disk full or storage-permission denied
        // -----------------------------------------------------------------
        is AppError.Storage -> storageRecovery(error)

        // -----------------------------------------------------------------
        // Hardware — camera, scanner, printer, payment terminal
        // -----------------------------------------------------------------
        is AppError.Hardware -> Recovery(
            title = "Hardware unavailable", // TODO(i18n)
            message = "${error.device}: ${error.reason}", // TODO(i18n)
            actions = listOf(Action.OpenSettings, Action.Dismiss),
        )

        // -----------------------------------------------------------------
        // Cancelled — user dismissed a sheet/scanner/picker; stay silent
        // -----------------------------------------------------------------
        AppError.Cancelled -> Recovery(
            title = "",
            message = "",
            actions = emptyList(),
        )

        // -----------------------------------------------------------------
        // Unknown — last resort
        // -----------------------------------------------------------------
        is AppError.Unknown -> Recovery(
            title = "Something went wrong", // TODO(i18n)
            message = "An unexpected error occurred. If this keeps happening, contact support.", // TODO(i18n)
            actions = listOf(Action.Retry, Action.ContactSupport),
        )
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private fun serverRecovery(error: AppError.Server): Recovery = when (error.status) {

        401, 403 -> Recovery(
            title = "Signed out — please log in", // TODO(i18n)
            message = "Your session has ended. Sign in again to continue.", // TODO(i18n)
            actions = listOf(Action.ReLogin),
            destructive = true,
        )

        408, 504 -> Recovery(
            title = "Server timeout", // TODO(i18n)
            message = "The server took too long to respond. Please try again.", // TODO(i18n)
            actions = listOf(Action.Retry),
        )

        409 -> Recovery(
            title = "Conflicting changes", // TODO(i18n)
            message = "Your changes conflict with a recent update. Reload and try again.", // TODO(i18n)
            actions = listOf(Action.Retry, Action.Dismiss),
        )

        429 -> Recovery(
            title = "Too many attempts", // TODO(i18n)
            message = buildString { // TODO(i18n)
                append("You're sending requests too quickly.")
                val hint = error.serverMessage
                if (!hint.isNullOrBlank() && hint.contains("retry", ignoreCase = true)) {
                    append(" $hint")
                } else {
                    append(" Please wait a moment before trying again.")
                }
            },
            actions = listOf(Action.Retry),
        )

        in 500..599 -> Recovery(
            title = "Server error", // TODO(i18n)
            message = "Something went wrong on our end (HTTP ${error.status}). Try again or contact support.", // TODO(i18n)
            actions = listOf(Action.Retry, Action.ContactSupport),
        )

        else -> Recovery(
            title = "Request failed", // TODO(i18n)
            message = "The request could not be completed (HTTP ${error.status}).", // TODO(i18n)
            actions = listOf(Action.Retry, Action.Dismiss),
        )
    }

    private fun authRecovery(error: AppError.Auth): Recovery = when (error.reason) {

        AppError.AuthReason.SessionExpired -> Recovery(
            title = "Session expired", // TODO(i18n)
            message = "Your session has timed out. Please sign in again.", // TODO(i18n)
            actions = listOf(Action.ReLogin),
            destructive = true,
        )

        AppError.AuthReason.SessionRevoked -> Recovery(
            title = "Session ended", // TODO(i18n)
            message = "An administrator ended your session. Please sign in again.", // TODO(i18n)
            actions = listOf(Action.ReLogin),
            destructive = true,
        )

        AppError.AuthReason.PermissionDenied -> Recovery(
            title = "Access denied", // TODO(i18n)
            message = "You don't have permission to do that. Ask your admin to adjust your role.", // TODO(i18n)
            actions = listOf(Action.OpenSettings, Action.Dismiss),
        )
    }

    private fun storageRecovery(error: AppError.Storage): Recovery {
        val reasonLower = error.reason.lowercase()
        return if (
            reasonLower.contains("permission") ||
            reasonLower.contains("denied") ||
            reasonLower.contains("access")
        ) {
            Recovery(
                title = "Storage permission denied", // TODO(i18n)
                message = "The app needs storage access. Grant permission in Settings.", // TODO(i18n)
                actions = listOf(Action.OpenSettings, Action.Dismiss),
            )
        } else {
            Recovery(
                title = "Out of storage", // TODO(i18n)
                message = "Your device is low on storage. Free up space and try again.", // TODO(i18n)
                actions = listOf(Action.FreeStorage, Action.Dismiss),
            )
        }
    }

    /**
     * Formats [AppError.FieldError] list into a user-facing message string.
     *
     * When [asBullets] is `true` renders as:
     * ```
     * • field: message
     * • field2: message2
     * ```
     * When `false` returns only the first error's message or a generic fallback.
     */
    private fun validationMessage(errors: List<AppError.FieldError>, asBullets: Boolean): String {
        if (errors.isEmpty()) {
            return "Some fields need attention." // TODO(i18n)
        }
        return if (asBullets) {
            errors.joinToString(separator = "\n") { fe ->
                "\u2022 ${fe.field}: ${fe.message}" // • field: message
            }
        } else {
            errors.first().message
        }
    }

    /** Capitalises the first character of a string without altering the rest. */
    private fun capitalize(s: String): String =
        if (s.isEmpty()) s else s[0].uppercaseChar() + s.substring(1)
}
