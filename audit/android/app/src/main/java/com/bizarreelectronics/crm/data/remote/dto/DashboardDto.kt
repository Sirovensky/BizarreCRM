package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * §3.17 L602 — DTO returned by `GET /dashboard/role-template/{role}`.
 *
 * The server may not yet implement this endpoint; callers must treat HTTP 404
 * as a signal to fall back to [DashboardViewModel.defaultTilesFor].
 *
 * @property defaultTiles  Ordered list of tile IDs for this role's default layout.
 * @property allowedTiles  Full set of tile IDs this role is permitted to show.
 *                         Tiles not in this set must be hidden and not offered in
 *                         the customization sheet.
 */
data class RoleTemplateDto(
    @SerializedName("default_tiles")
    val defaultTiles: List<String> = emptyList(),
    @SerializedName("allowed_tiles")
    val allowedTiles: Set<String> = emptySet(),
)
