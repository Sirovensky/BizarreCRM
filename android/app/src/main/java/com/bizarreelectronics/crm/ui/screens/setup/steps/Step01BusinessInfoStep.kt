package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 1 — Business info.
 *
 * Collects: shop_name, address, phone, timezone, shop_type.
 * All fields are required except address (blank is allowed but recommended).
 *
 * Server contract (step_index=1):
 *   { shop_name: String, address: String, phone: String,
 *     timezone: String, shop_type: "repair"|"retail"|"both" }
 *
 * [data] — current saved values for this step (may be empty on first entry).
 * [onDataChange] — called with the full updated field map on any change.
 */
@Composable
fun BusinessInfoStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var shopName  by remember { mutableStateOf(data["shop_name"]?.toString() ?: "") }
    var address   by remember { mutableStateOf(data["address"]?.toString() ?: "") }
    var phone     by remember { mutableStateOf(data["phone"]?.toString() ?: "") }
    var timezone  by remember { mutableStateOf(data["timezone"]?.toString() ?: "America/New_York") }
    var shopType  by remember { mutableStateOf(data["shop_type"]?.toString() ?: "repair") }

    fun emit() {
        onDataChange(mapOf(
            "shop_name" to shopName,
            "address"   to address,
            "phone"     to phone,
            "timezone"  to timezone,
            "shop_type" to shopType,
        ))
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Business Info", style = MaterialTheme.typography.titleLarge)

        OutlinedTextField(
            value = shopName,
            onValueChange = { shopName = it; emit() },
            label = { Text("Shop name *") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
        )
        OutlinedTextField(
            value = address,
            onValueChange = { address = it; emit() },
            label = { Text("Address") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 2,
            maxLines = 3,
        )
        OutlinedTextField(
            value = phone,
            onValueChange = { phone = it; emit() },
            label = { Text("Phone *") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
        )
        OutlinedTextField(
            value = timezone,
            onValueChange = { timezone = it; emit() },
            label = { Text("Timezone *") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            supportingText = { Text("e.g. America/New_York") },
        )

        Text("Shop type *", style = MaterialTheme.typography.bodyMedium)
        val types = listOf("repair" to "Repair", "retail" to "Retail", "both" to "Both")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            types.forEach { (value, label) ->
                FilterChip(
                    selected = shopType == value,
                    onClick  = { shopType = value; emit() },
                    label    = { Text(label) },
                )
            }
        }
    }
}
