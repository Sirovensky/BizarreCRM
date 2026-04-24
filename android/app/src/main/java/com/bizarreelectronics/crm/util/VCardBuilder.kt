package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity

/**
 * Builds a vCard 3.0 string from a [CustomerEntity] (plan:L903).
 *
 * The resulting string can be shared as a `text/x-vcard` attachment via
 * [android.content.Intent.ACTION_SEND].
 *
 * @param customer Source customer entity.
 * @return vCard 3.0 formatted string.
 */
object VCardBuilder {

    fun build(customer: CustomerEntity): String {
        val fullName = listOfNotNull(customer.firstName, customer.lastName)
            .joinToString(" ")
            .ifBlank { "Unknown" }

        val firstName = customer.firstName?.escapedVCard() ?: ""
        val lastName = customer.lastName?.escapedVCard() ?: ""

        return buildString {
            appendLine("BEGIN:VCARD")
            appendLine("VERSION:3.0")
            appendLine("FN:${fullName.escapedVCard()}")
            appendLine("N:$lastName;$firstName;;;")

            customer.organization?.takeIf { it.isNotBlank() }?.let {
                appendLine("ORG:${it.escapedVCard()}")
            }

            customer.mobile?.takeIf { it.isNotBlank() }?.let {
                appendLine("TEL;TYPE=CELL:$it")
            }
            customer.phone?.takeIf { it.isNotBlank() }?.let {
                appendLine("TEL;TYPE=WORK:$it")
            }

            customer.email?.takeIf { it.isNotBlank() }?.let {
                appendLine("EMAIL;TYPE=INTERNET:${it.escapedVCard()}")
            }

            val adr = buildList {
                customer.address1?.let { add(it) }
                customer.address2?.let { add(it) }
            }.joinToString("\\n")
            val city = customer.city ?: ""
            val state = customer.state ?: ""
            val postcode = customer.postcode ?: ""
            val country = customer.country ?: ""
            if (adr.isNotBlank() || city.isNotBlank()) {
                appendLine("ADR;TYPE=WORK:;;${adr.escapedVCard()};${city.escapedVCard()};${state.escapedVCard()};${postcode.escapedVCard()};${country.escapedVCard()}")
            }

            customer.tags?.takeIf { it.isNotBlank() }?.let {
                appendLine("CATEGORIES:${it.escapedVCard()}")
            }

            appendLine("END:VCARD")
        }
    }

    private fun String.escapedVCard(): String =
        replace("\\", "\\\\")
            .replace(",", "\\,")
            .replace(";", "\\;")
            .replace("\n", "\\n")
}
