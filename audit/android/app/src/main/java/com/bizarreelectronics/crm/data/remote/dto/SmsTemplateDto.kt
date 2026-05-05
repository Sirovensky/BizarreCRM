package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * Wire-level DTO for a single SMS template returned by GET /sms/templates.
 * Server column name is `content`; the `name` and `id` fields are standard.
 * Category is optional — templates without one omit the field entirely.
 */
data class SmsTemplateDto(
    @SerializedName("id")
    val id: Long,
    @SerializedName("name")
    val name: String,
    /** Server column is `content`. Body is what gets inserted into the compose field. */
    @SerializedName("content")
    val body: String,
    @SerializedName("category")
    val category: String? = null,
)

/**
 * Wrapper matching the server envelope:
 * `{ "templates": [...], "available_variables": [...] }`
 */
data class SmsTemplateListData(
    val templates: List<SmsTemplateDto>,
    @SerializedName("available_variables")
    val availableVariables: List<String>? = null,
)
