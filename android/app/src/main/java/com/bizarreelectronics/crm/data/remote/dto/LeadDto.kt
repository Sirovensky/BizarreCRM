package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── List response wrappers ───

data class LeadListData(
    val leads: List<LeadListItem>,
    val pagination: Pagination? = null
)

data class AppointmentListData(
    val appointments: List<AppointmentDetail>,
    val pagination: Pagination? = null
)

// ─── List item (summary) ───

data class LeadListItem(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val email: String?,
    val phone: String?,
    val status: String?,
    @SerializedName("lead_score")
    val leadScore: Int?,
    val source: String?,
    @SerializedName("assigned_to")
    val assignedTo: Long?,
    @SerializedName("assigned_first_name")
    val assignedFirstName: String?,
    @SerializedName("assigned_last_name")
    val assignedLastName: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
) {
    val fullName: String get() = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { "Unknown" }
    val assignedName: String? get() = listOfNotNull(assignedFirstName, assignedLastName).joinToString(" ").ifBlank { null }
}

// ─── Detail ───

data class LeadDetail(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val email: String?,
    val phone: String?,
    @SerializedName("zip_code")
    val zipCode: String?,
    val address: String?,
    val status: String?,
    @SerializedName("referred_by")
    val referredBy: String?,
    @SerializedName("assigned_to")
    val assignedTo: Long?,
    val source: String?,
    val notes: String?,
    @SerializedName("lost_reason")
    val lostReason: String?,
    @SerializedName("lead_score")
    val leadScore: Int?,
    @SerializedName("assigned_first_name")
    val assignedFirstName: String?,
    @SerializedName("assigned_last_name")
    val assignedLastName: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    @SerializedName("is_deleted")
    val isDeleted: Int?,
    val devices: List<LeadDevice>? = null,
    val appointments: List<AppointmentDetail>? = null,
    val reminders: List<LeadReminder>? = null,
) {
    val fullName: String get() = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { "Unknown" }
    val assignedName: String? get() = listOfNotNull(assignedFirstName, assignedLastName).joinToString(" ").ifBlank { null }
}

// ─── Lead device ───

data class LeadDevice(
    val id: Long,
    @SerializedName("lead_id")
    val leadId: Long,
    @SerializedName("device_name")
    val deviceName: String?,
    @SerializedName("repair_type")
    val repairType: String?,
    @SerializedName("service_type")
    val serviceType: String?,
    @SerializedName("service_id")
    val serviceId: Long?,
    val price: Double?,
    val tax: Double?,
    val problem: String?,
    @SerializedName("customer_notes")
    val customerNotes: String?,
    @SerializedName("security_code")
    val securityCode: String?,
    @SerializedName("start_time")
    val startTime: String?,
    @SerializedName("end_time")
    val endTime: String?,
)

// ─── Appointment ───

data class AppointmentDetail(
    val id: Long,
    @SerializedName("lead_id")
    val leadId: Long?,
    @SerializedName("customer_id")
    val customerId: Long?,
    val title: String?,
    @SerializedName("start_time")
    val startTime: String?,
    @SerializedName("end_time")
    val endTime: String?,
    @SerializedName("assigned_to")
    val assignedTo: Long?,
    val status: String?,
    val notes: String?,
    @SerializedName("customer_first_name")
    val customerFirstName: String?,
    @SerializedName("customer_last_name")
    val customerLastName: String?,
    @SerializedName("assigned_first_name")
    val assignedFirstName: String?,
    @SerializedName("assigned_last_name")
    val assignedLastName: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
) {
    val customerName: String? get() = listOfNotNull(customerFirstName, customerLastName).joinToString(" ").ifBlank { null }
    val assignedName: String? get() = listOfNotNull(assignedFirstName, assignedLastName).joinToString(" ").ifBlank { null }
}

// ─── Reminder ───

data class LeadReminder(
    val id: Long,
    @SerializedName("lead_id")
    val leadId: Long,
    @SerializedName("remind_at")
    val remindAt: String?,
    val note: String?,
    @SerializedName("created_by")
    val createdBy: Long?,
    @SerializedName("is_dismissed")
    val isDismissed: Int?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("created_by_first_name")
    val createdByFirstName: String?,
    @SerializedName("created_by_last_name")
    val createdByLastName: String?,
) {
    val createdByName: String? get() = listOfNotNull(createdByFirstName, createdByLastName).joinToString(" ").ifBlank { null }
}

// ─── Request bodies ───

data class CreateLeadRequest(
    @SerializedName("first_name")
    val firstName: String,
    @SerializedName("last_name")
    val lastName: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val address: String? = null,
    @SerializedName("zip_code")
    val zipCode: String? = null,
    val status: String? = null,
    val source: String? = null,
    @SerializedName("referred_by")
    val referredBy: String? = null,
    @SerializedName("assigned_to")
    val assignedTo: Long? = null,
    val notes: String? = null,
    val devices: List<CreateLeadDeviceRequest>? = null,
)

data class CreateLeadDeviceRequest(
    @SerializedName("device_name")
    val deviceName: String,
    @SerializedName("repair_type")
    val repairType: String? = null,
    @SerializedName("service_type")
    val serviceType: String? = null,
    @SerializedName("service_id")
    val serviceId: Long? = null,
    val price: Double? = null,
    val problem: String? = null,
    @SerializedName("customer_notes")
    val customerNotes: String? = null,
    @SerializedName("security_code")
    val securityCode: String? = null,
)

data class UpdateLeadRequest(
    @SerializedName("first_name")
    val firstName: String? = null,
    @SerializedName("last_name")
    val lastName: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val address: String? = null,
    @SerializedName("zip_code")
    val zipCode: String? = null,
    val status: String? = null,
    val source: String? = null,
    @SerializedName("referred_by")
    val referredBy: String? = null,
    @SerializedName("assigned_to")
    val assignedTo: Long? = null,
    val notes: String? = null,
    @SerializedName("lost_reason")
    val lostReason: String? = null,
    val devices: List<CreateLeadDeviceRequest>? = null,
)

data class CreateAppointmentRequest(
    @SerializedName("lead_id")
    val leadId: Long? = null,
    @SerializedName("customer_id")
    val customerId: Long? = null,
    val title: String,
    @SerializedName("start_time")
    val startTime: String,
    @SerializedName("end_time")
    val endTime: String? = null,
    @SerializedName("assigned_to")
    val assignedTo: Long? = null,
    val notes: String? = null,
)
