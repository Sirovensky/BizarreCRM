package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class CustomerListItem(
    val id: Long,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val email: String?,
    val phone: String?,
    val mobile: String?,
    val organization: String?,
    val city: String?,
    val state: String?,
    @SerializedName("customer_group_name")
    val customerGroupName: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("ticket_count")
    val ticketCount: Int?
)

data class CustomerDetail(
    val id: Long,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val title: String?,
    val email: String?,
    @SerializedName("email_opt_in")
    val emailOptIn: Int?,
    @SerializedName("sms_opt_in")
    val smsOptIn: Int?,
    val phone: String?,
    val mobile: String?,
    val phones: List<CustomerPhone>?,
    val emails: List<CustomerEmail>?,
    val address1: String?,
    val address2: String?,
    val city: String?,
    val state: String?,
    val country: String?,
    val postcode: String?,
    val organization: String?,
    @SerializedName("contact_person")
    val contactPerson: String?,
    @SerializedName("contact_person_relation")
    val contactPersonRelation: String?,
    val type: String?,
    @SerializedName("customer_group_id")
    val customerGroupId: Long?,
    @SerializedName("customer_group_name")
    val customerGroupName: String?,
    @SerializedName("customer_tags")
    val customerTags: String?,
    val comments: String?,
    val image: String?,
    @SerializedName("tax_class_id")
    val taxClassId: Long?,
    @SerializedName("referred_by")
    val referredBy: String?,
    val source: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    val tickets: List<TicketListItem>?,
    val invoices: List<InvoiceListItem>?,
    val assets: List<CustomerAsset>?
)

data class CustomerPhone(
    val id: Long?,
    val phone: String,
    val label: String?
)

data class CustomerEmail(
    val id: Long?,
    val email: String,
    val label: String?
)

data class CustomerAsset(
    val id: Long,
    val name: String?,
    @SerializedName("device_model_id")
    val deviceModelId: Long?,
    val imei: String?,
    val serial: String?,
    val color: String?,
    val notes: String?,
    @SerializedName("created_at")
    val createdAt: String?
)

data class CreateCustomerRequest(
    @SerializedName("first_name")
    val firstName: String,
    @SerializedName("last_name")
    val lastName: String?,
    val email: String? = null,
    val phone: String? = null,
    val mobile: String? = null,
    val address1: String? = null,
    val address2: String? = null,
    val city: String? = null,
    val state: String? = null,
    val country: String? = null,
    val postcode: String? = null,
    val organization: String? = null,
    @SerializedName("contact_person")
    val contactPerson: String? = null,
    @SerializedName("contact_person_relation")
    val contactPersonRelation: String? = null,
    val type: String? = "individual",
    @SerializedName("customer_group_id")
    val customerGroupId: Long? = null,
    @SerializedName("customer_tags")
    val customerTags: String? = null,
    val comments: String? = null,
    @SerializedName("email_opt_in")
    val emailOptIn: Int? = 1,
    @SerializedName("sms_opt_in")
    val smsOptIn: Int? = 1,
    @SerializedName("referred_by")
    val referredBy: String? = null,
    val phones: List<CustomerPhone>? = null,
    val emails: List<CustomerEmail>? = null,
    /**
     * Client-generated idempotency key (UUID). The server is expected to dedupe
     * concurrent/retried creates by this value so that a retried POST after a
     * transient failure does not produce duplicate customers. See AP5.
     */
    @SerializedName("client_request_id")
    val clientRequestId: String? = null
)

data class UpdateCustomerRequest(
    @SerializedName("first_name")
    val firstName: String? = null,
    @SerializedName("last_name")
    val lastName: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val mobile: String? = null,
    val address1: String? = null,
    val address2: String? = null,
    val city: String? = null,
    val state: String? = null,
    val country: String? = null,
    val postcode: String? = null,
    val organization: String? = null,
    @SerializedName("contact_person")
    val contactPerson: String? = null,
    @SerializedName("contact_person_relation")
    val contactPersonRelation: String? = null,
    val type: String? = null,
    @SerializedName("customer_group_id")
    val customerGroupId: Long? = null,
    @SerializedName("customer_tags")
    val customerTags: String? = null,
    val comments: String? = null,
    @SerializedName("email_opt_in")
    val emailOptIn: Int? = null,
    @SerializedName("sms_opt_in")
    val smsOptIn: Int? = null,
    @SerializedName("referred_by")
    val referredBy: String? = null,
    val phones: List<CustomerPhone>? = null,
    val emails: List<CustomerEmail>? = null
)
