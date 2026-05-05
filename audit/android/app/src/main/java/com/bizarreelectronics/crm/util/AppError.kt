package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.HttpException
import java.io.IOException

/**
 * §1.6 — central error taxonomy used by ViewModels + repositories so the UI
 * layer can render consistent recovery actions instead of raw exception
 * messages. Server text is preserved on `Server` and `Validation` branches
 * but never shown verbatim outside of those two cases.
 *
 * Each branch exposes a [title], [message], and [suggestedActions] so the
 * UI surface can render a sheet / banner / dialog without per-branch logic.
 *
 * Construction goes through [from] which inspects exceptions + ApiResponse
 * envelopes and returns the most specific branch that fits.
 */
sealed class AppError(
    val title: String,
    val message: String,
    val suggestedActions: List<AppErrorAction>,
) {
    /**
     * Network is unreachable, DNS failed, or socket timeout. Recovery is
     * usually "wait and retry"; the §20 sync queue catches writes that miss.
     */
    data class Network(val cause: Throwable?) : AppError(
        title = "You're offline",
        message = "We can't reach the server right now. Your work is saved and will sync when you're back online.",
        suggestedActions = listOf(AppErrorAction.Retry, AppErrorAction.Dismiss),
    )

    /** 5xx, 4xx other than the specialised branches below. */
    data class Server(
        val status: Int,
        val serverMessage: String?,
        val requestId: String?,
    ) : AppError(
        title = "Server error",
        message = serverMessage?.takeIf { it.isNotBlank() }
            ?: "Something went wrong on the server (HTTP $status). Try again, or report this if it keeps happening.",
        suggestedActions = listOf(
            AppErrorAction.Retry,
            AppErrorAction.ContactSupport(requestId),
            AppErrorAction.Dismiss,
        ),
    )

    /** 401 / 403 — session expired, role missing. */
    data class Auth(val reason: AuthReason) : AppError(
        title = when (reason) {
            AuthReason.SessionExpired -> "You've been signed out"
            AuthReason.PermissionDenied -> "You don't have access"
            AuthReason.SessionRevoked -> "Session ended"
        },
        message = when (reason) {
            AuthReason.SessionExpired -> "Sign back in to continue."
            AuthReason.PermissionDenied -> "Ask your admin to give you access to this."
            AuthReason.SessionRevoked -> "An admin signed you out from another device."
        },
        suggestedActions = when (reason) {
            AuthReason.PermissionDenied -> listOf(AppErrorAction.Dismiss)
            else -> listOf(AppErrorAction.SignIn, AppErrorAction.Dismiss)
        },
    )

    /** 422 — server-side field validation. */
    data class Validation(val errors: List<FieldError>) : AppError(
        title = "Please check the form",
        message = errors.firstOrNull()?.message ?: "Some fields need attention.",
        suggestedActions = listOf(AppErrorAction.Dismiss),
    )

    /** 404 — entity referenced by the user no longer exists. */
    data class NotFound(val entity: String, val id: String?) : AppError(
        title = "Not found",
        message = "We couldn't find that ${entity.lowercase()}. It may have been deleted.",
        suggestedActions = listOf(AppErrorAction.Dismiss),
    )

    /** 409 — concurrent edit detected. */
    data class Conflict(val serverUpdatedAt: String?) : AppError(
        title = "Edit conflict",
        message = "Someone else updated this in the meantime. Reload to pick up their changes.",
        suggestedActions = listOf(AppErrorAction.Reload, AppErrorAction.Dismiss),
    )

    /** Local storage / SQLCipher / disk-full / passphrase failure. */
    data class Storage(val reason: String) : AppError(
        title = "Storage error",
        message = reason,
        suggestedActions = listOf(AppErrorAction.Dismiss),
    )

    /** Hardware (camera / scanner / printer / payment terminal) failure. */
    data class Hardware(val device: String, val reason: String) : AppError(
        title = "$device problem",
        message = reason,
        suggestedActions = listOf(AppErrorAction.Retry, AppErrorAction.Dismiss),
    )

    /** User canceled a sheet / scanner / picker. Not really an error — UI usually swallows. */
    data object Cancelled : AppError(
        title = "Cancelled",
        message = "",
        suggestedActions = emptyList(),
    )

    /** Last-resort branch for anything that doesn't fit the others. */
    data class Unknown(val cause: Throwable?) : AppError(
        title = "Unexpected error",
        message = cause?.message ?: "Try again. If this keeps happening, contact your admin.",
        suggestedActions = listOf(AppErrorAction.Retry, AppErrorAction.Dismiss),
    )

    enum class AuthReason { SessionExpired, PermissionDenied, SessionRevoked }

    data class FieldError(val field: String, val message: String)

    companion object {
        /** Map any throwable + optional response into the closest [AppError]. */
        fun from(throwable: Throwable, requestId: String? = null): AppError = when (throwable) {
            is IOException -> Network(throwable)
            is HttpException -> {
                val code = throwable.code()
                val msg = throwable.message
                when (code) {
                    401 -> Auth(AuthReason.SessionExpired)
                    403 -> Auth(AuthReason.PermissionDenied)
                    404 -> NotFound("item", null)
                    409 -> Conflict(serverUpdatedAt = null)
                    422 -> Validation(emptyList())
                    in 500..599 -> Server(code, msg, requestId)
                    else -> Server(code, msg, requestId)
                }
            }
            else -> Unknown(throwable)
        }

        /** Wrap an ApiResponse failure into AppError without raising. */
        fun fromResponse(response: ApiResponse<*>, status: Int = 500, requestId: String? = null): AppError {
            if (response.success) return Unknown(null)
            return Server(status, response.message, requestId)
        }
    }
}

sealed class AppErrorAction(val label: String) {
    data object Retry : AppErrorAction("Try again")
    data object Reload : AppErrorAction("Reload")
    data object Dismiss : AppErrorAction("Dismiss")
    data object SignIn : AppErrorAction("Sign in")
    data class ContactSupport(val requestId: String?) : AppErrorAction("Contact support")
    data object OpenSettings : AppErrorAction("Open settings")
}
