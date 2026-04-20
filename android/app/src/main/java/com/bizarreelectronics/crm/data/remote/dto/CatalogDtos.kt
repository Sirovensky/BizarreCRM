package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class ManufacturerItem(
    val id: Long,
    val name: String,
    @SerializedName("model_count")
    val modelCount: Int = 0
)

data class DeviceModelItem(
    val id: Long,
    val name: String,
    val category: String?,
    @SerializedName("manufacturer_id")
    val manufacturerId: Long?,
    @SerializedName("manufacturer_name")
    val manufacturerName: String?,
    @SerializedName("is_popular")
    val isPopular: Int = 0,
    @SerializedName("repair_count")
    val repairCount: Int = 0,
    @SerializedName("release_year")
    val releaseYear: Int? = null
)
