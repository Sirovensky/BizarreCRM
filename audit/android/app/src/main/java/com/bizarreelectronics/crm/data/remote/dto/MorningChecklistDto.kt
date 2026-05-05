package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * §36 L585–L588 — DTOs for the morning-open checklist feature.
 *
 * All endpoints under `tenants/me/morning-checklist` and
 * `morning-checklist/complete` are treated as optional — HTTP 404 is
 * silently tolerated and the app falls back to built-in defaults.
 */

/**
 * A single checklist step as returned by `GET /tenants/me/morning-checklist`.
 *
 * Tenant-customizable contract: the server may return any non-empty list of
 * steps. If the endpoint returns 404 (or a parsing error occurs), the
 * [MorningChecklistDefaults.steps] list is used instead.
 *
 * @property id       Stable step identifier (1-based integer by convention).
 * @property title    Short action label shown as the checkbox row title.
 * @property subtitle Optional helper text shown below the title.
 * @property requiresInput When true the step opens a dialog (e.g. cash-count entry).
 * @property deepLinkRoute Internal nav route for the "View list →" button, or null.
 */
data class ChecklistStepDto(
    val id: Int,
    val title: String,
    val subtitle: String = "",
    @SerializedName("requires_input") val requiresInput: Boolean = false,
    @SerializedName("deep_link_route") val deepLinkRoute: String? = null,
)

/**
 * Wrapper returned by `GET /tenants/me/morning-checklist`.
 *
 * @property steps Ordered list of steps for today's morning-open procedure.
 */
data class MorningChecklistConfigDto(
    val steps: List<ChecklistStepDto> = emptyList(),
)

/**
 * Body posted to `POST /morning-checklist/complete`.
 *
 * 404 on this endpoint is tolerated — the local completion state is always
 * persisted regardless of server availability.
 *
 * @property dateKey     ISO-date string (yyyy-MM-dd) for which the checklist was completed.
 * @property staffId     ID of the staff member who completed the checklist.
 * @property completedSteps Set of step IDs that were checked off.
 * @property completedAtMs Epoch-ms timestamp of final completion.
 */
data class MorningChecklistCompleteBody(
    @SerializedName("date_key") val dateKey: String,
    @SerializedName("staff_id") val staffId: Long,
    @SerializedName("completed_steps") val completedSteps: List<Int>,
    @SerializedName("completed_at_ms") val completedAtMs: Long,
)

/**
 * §3.15 L589 — Body posted to `POST /morning-checklist/skip`.
 *
 * 404 on this endpoint is tolerated — the skip is recorded locally regardless.
 * The server writes this event into the tenant audit log when the endpoint ships.
 *
 * @property dateKey   ISO-date string (yyyy-MM-dd) for the day that was skipped.
 * @property staffId   ID of the staff member who skipped.
 * @property skippedAtMs Epoch-ms timestamp of skip action.
 */
data class MorningChecklistSkipBody(
    @SerializedName("date_key") val dateKey: String,
    @SerializedName("staff_id") val staffId: Long,
    @SerializedName("skipped_at_ms") val skippedAtMs: Long,
)
