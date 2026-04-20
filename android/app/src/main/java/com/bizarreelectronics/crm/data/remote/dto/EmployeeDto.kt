package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * Request body for POST /settings/users — admin-only employee creation.
 *
 * Mirrors the server schema at packages/server/src/routes/settings.routes.ts
 * (line 770). Username, firstName and lastName are required by the server;
 * everything else is optional:
 *   - password: if omitted the account is created with passwordSet=0 and the
 *     user must set it on first login.
 *   - pin: plain string, hashed with bcrypt server-side.
 *   - role: defaults to "technician" server-side if omitted, but we always
 *     send an explicit value from the UI dropdown.
 */
data class CreateEmployeeRequest(
    val username: String,
    val email: String? = null,
    val password: String? = null,
    @SerializedName("first_name")
    val firstName: String,
    @SerializedName("last_name")
    val lastName: String,
    val role: String = "technician",
    val pin: String? = null,
)
