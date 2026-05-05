package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class ConditionCheckItem(
    val id: Long,
    val label: String,
    @SerializedName("sort_order")
    val sortOrder: Int = 0
)
