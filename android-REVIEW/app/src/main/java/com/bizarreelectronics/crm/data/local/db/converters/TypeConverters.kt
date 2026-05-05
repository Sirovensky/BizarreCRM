package com.bizarreelectronics.crm.data.local.db.converters

import androidx.room.TypeConverter
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

class Converters {

    private val gson = Gson()

    @TypeConverter
    fun fromStringList(value: String?): List<String> {
        if (value == null) return emptyList()
        return try {
            gson.fromJson(value, object : TypeToken<List<String>>() {}.type)
        } catch (_: Exception) {
            emptyList()
        }
    }

    @TypeConverter
    fun toStringList(list: List<String>?): String? {
        return if (list.isNullOrEmpty()) null else gson.toJson(list)
    }

    @TypeConverter
    fun fromStringMap(value: String?): Map<String, String> {
        if (value == null) return emptyMap()
        return try {
            gson.fromJson(value, object : TypeToken<Map<String, String>>() {}.type)
        } catch (_: Exception) {
            emptyMap()
        }
    }

    @TypeConverter
    fun toStringMap(map: Map<String, String>?): String? {
        return if (map.isNullOrEmpty()) null else gson.toJson(map)
    }
}
