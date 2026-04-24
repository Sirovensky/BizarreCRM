package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import com.bizarreelectronics.crm.ui.screens.pos.AttachedCustomer
import com.bizarreelectronics.crm.ui.screens.pos.CartLine
import com.bizarreelectronics.crm.ui.screens.pos.DiscountMode
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import com.bizarreelectronics.crm.ui.screens.pos.TipConfig
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import java.util.Locale

private fun Long.formatMoney(): String = "$${String.format(Locale.US, "%.2f", this / 100.0)}"

/**
 * Cart panel — line items with qty stepper / price edit / discount / remove,
 * cart-level discount, customer attach, tip, park button.
 *
 * Plan §16.1 L1796-L1801.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosCart(
    cart: PosCartState,
    parkedCount: Int,
    onSetQty: (lineId: String, qty: Int) -> Unit,
    onSetUnitPrice: (lineId: String, priceCents: Long) -> Unit,
    onSetLineDiscount: (lineId: String, discountCents: Long) -> Unit,
    onRemoveLine: (lineId: String) -> Unit,
    onSetCartDiscount: (cents: Long, mode: DiscountMode) -> Unit,
    onSetTip: (TipConfig) -> Unit,
    onAttachCustomer: (AttachedCustomer?) -> Unit,
    onPark: () -> Unit,
    onTender: () -> Unit,
    // Customer picker state + callbacks (search / create new / walk-in)
    customerSearchQuery: String,
    customerSearchResults: List<com.bizarreelectronics.crm.data.remote.dto.CustomerListItem>,
    customerSearchLoading: Boolean,
    onCustomerSearchQuery: (String) -> Unit,
    onSelectExistingCustomer: (com.bizarreelectronics.crm.data.remote.dto.CustomerListItem) -> Unit,
    onSelectWalkInCustomer: () -> Unit,
    onCreateNewCustomer: (firstName: String, lastName: String?, phone: String?, email: String?) -> Unit,
    modifier: Modifier = Modifier,
    // Role-gate: if false, unit price fields are read-only
    canEditPrice: Boolean = true,
) {
    var showCustomerPicker by remember { mutableStateOf(false) }
    var showDiscountDialog by remember { mutableStateOf(false) }
    var showTipDialog by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxSize()) {

        // ── Customer chip ─────────────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (cart.customer != null) {
                InputChip(
                    selected = true,
                    onClick = { showCustomerPicker = true },
                    label = { Text(cart.customer.name, maxLines = 1) },
                    leadingIcon = {
                        Icon(Icons.Default.Person, contentDescription = null, modifier = Modifier.size(16.dp))
                    },
                    trailingIcon = {
                        IconButton(
                            onClick = { onAttachCustomer(null) },
                            modifier = Modifier.size(20.dp),
                        ) {
                            Icon(Icons.Default.Remove, contentDescription = "Remove customer", modifier = Modifier.size(14.dp))
                        }
                    },
                    modifier = Modifier.semantics {
                        contentDescription = "Customer: ${cart.customer.name}. Tap to change."
                    },
                )
            } else {
                AssistChip(
                    onClick = { showCustomerPicker = true },
                    label = { Text("Add Customer") },
                    leadingIcon = {
                        Icon(Icons.Default.PersonAdd, contentDescription = null, modifier = Modifier.size(16.dp))
                    },
                    modifier = Modifier.semantics {
                        contentDescription = "Add customer to cart"
                        role = Role.Button
                    },
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            // Park cart
            AssistChip(
                onClick = onPark,
                label = { Text("Park") },
                enabled = cart.lines.isNotEmpty(),
                modifier = Modifier.semantics {
                    contentDescription = if (parkedCount > 0) "Park cart ($parkedCount parked)" else "Park cart"
                    role = Role.Button
                },
            )
        }

        // ── Line items ────────────────────────────────────────────────────
        if (cart.lines.isEmpty()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "Cart is empty",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                items(cart.lines, key = { it.id }) { line ->
                    CartLineRow(
                        line = line,
                        canEditPrice = canEditPrice,
                        onSetQty = { onSetQty(line.id, it) },
                        onSetUnitPrice = { onSetUnitPrice(line.id, it) },
                        onSetDiscount = { onSetLineDiscount(line.id, it) },
                        onRemove = { onRemoveLine(line.id) },
                    )
                }
            }
        }

        // ── Cart-level controls ───────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            AssistChip(
                onClick = { showDiscountDialog = true },
                label = {
                    val label = if (cart.cartDiscountCents > 0) {
                        "Discount: ${cart.cartDiscountCents.formatMoney()}"
                    } else "Discount"
                    Text(label)
                },
                modifier = Modifier.semantics { role = Role.Button },
            )
            AssistChip(
                onClick = { showTipDialog = true },
                label = {
                    val label = if (cart.tip.enabled && cart.tipCents > 0) {
                        "Tip: ${cart.tipCents.formatMoney()}"
                    } else "Tip"
                    Text(label)
                },
                modifier = Modifier.semantics { role = Role.Button },
            )
        }

        // ── Bottom bar (totals + Tender) ──────────────────────────────────
        PosBottomBar(
            cart = cart,
            onTender = onTender,
        )
    }

    // ── Dialogs ───────────────────────────────────────────────────────────
    if (showCustomerPicker) {
        CustomerPickerDialog(
            searchQuery = customerSearchQuery,
            searchResults = customerSearchResults,
            searchLoading = customerSearchLoading,
            onSearchQueryChange = onCustomerSearchQuery,
            onSelectExisting = onSelectExistingCustomer,
            onSelectWalkIn = onSelectWalkInCustomer,
            onCreateNew = onCreateNewCustomer,
            onDismiss = { showCustomerPicker = false },
        )
    }

    if (showDiscountDialog) {
        CartDiscountDialog(
            current = cart.cartDiscountCents,
            mode = cart.cartDiscountMode,
            subtotalCents = cart.subtotalCents,
            onApply = { cents, mode ->
                onSetCartDiscount(cents, mode)
                showDiscountDialog = false
            },
            onDismiss = { showDiscountDialog = false },
        )
    }

    if (showTipDialog) {
        TipDialog(
            current = cart.tip,
            subtotalCents = cart.subtotalCents,
            onApply = { config ->
                onSetTip(config)
                showTipDialog = false
            },
            onDismiss = { showTipDialog = false },
        )
    }
}

// ─── Cart line row ────────────────────────────────────────────────────────────

@Composable
private fun CartLineRow(
    line: CartLine,
    canEditPrice: Boolean,
    onSetQty: (Int) -> Unit,
    onSetUnitPrice: (Long) -> Unit,
    onSetDiscount: (Long) -> Unit,
    onRemove: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    line.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                IconButton(
                    onClick = onRemove,
                    modifier = Modifier.semantics { contentDescription = "Remove ${line.name}" },
                ) {
                    Icon(Icons.Default.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                }
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // Qty stepper
                IconButton(
                    onClick = { onSetQty(line.qty - 1) },
                    modifier = Modifier
                        .size(32.dp)
                        .semantics { contentDescription = "Decrease quantity" },
                ) {
                    Icon(Icons.Default.Remove, contentDescription = null, modifier = Modifier.size(14.dp))
                }
                Text("${line.qty}", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                IconButton(
                    onClick = { onSetQty(line.qty + 1) },
                    modifier = Modifier
                        .size(32.dp)
                        .semantics { contentDescription = "Increase quantity" },
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(14.dp))
                }
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    line.totalCents.formatMoney(),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            // Unit price (role-gated)
            if (canEditPrice) {
                var priceInput by remember(line.id) {
                    mutableStateOf(String.format(Locale.US, "%.2f", line.unitPriceCents / 100.0))
                }
                OutlinedTextField(
                    value = priceInput,
                    onValueChange = { v ->
                        priceInput = v
                        v.toDoubleOrNull()?.let { onSetUnitPrice((it * 100).toLong()) }
                    },
                    label = { Text("Unit price") },
                    leadingIcon = { Text("$") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                Text(
                    "@ ${line.unitPriceCents.formatMoney()} each",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── Bottom bar ───────────────────────────────────────────────────────────────

@Composable
private fun PosBottomBar(
    cart: PosCartState,
    onTender: () -> Unit,
) {
    Surface(
        tonalElevation = 8.dp,
        shadowElevation = 8.dp,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Subtotal", style = MaterialTheme.typography.bodySmall)
                Text(cart.subtotalCents.formatMoney(), style = MaterialTheme.typography.bodySmall)
            }
            if (cart.taxCents > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Tax", style = MaterialTheme.typography.bodySmall)
                    Text(cart.taxCents.formatMoney(), style = MaterialTheme.typography.bodySmall)
                }
            }
            if (cart.discountCents > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Discount", style = MaterialTheme.typography.bodySmall)
                    Text("-${cart.discountCents.formatMoney()}", style = MaterialTheme.typography.bodySmall, color = SuccessGreen)
                }
            }
            if (cart.tipCents > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Tip", style = MaterialTheme.typography.bodySmall)
                    Text(cart.tipCents.formatMoney(), style = MaterialTheme.typography.bodySmall)
                }
            }
            Divider()
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Total", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(cart.totalCents.formatMoney(), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            Button(
                onClick = onTender,
                enabled = cart.lines.isNotEmpty(),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .semantics {
                        contentDescription = "Tender ${cart.totalCents.formatMoney()}"
                        role = Role.Button
                    },
            ) {
                Text(
                    "Tender  ${cart.totalCents.formatMoney()}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

// ─── Customer picker dialog ───────────────────────────────────────────────────
// User-facing requirement: three first-class options — Search / New / Walk-in.
// Walk-in tile rendered as dashed-border ghost so cashiers see it's a fallback.
// Functionality parity with web, not visual — web shows these three; we must
// mirror the choice set, not the exact styling.

@Composable
internal fun CustomerPickerDialog(
    searchQuery: String,
    searchResults: List<com.bizarreelectronics.crm.data.remote.dto.CustomerListItem>,
    searchLoading: Boolean,
    onSearchQueryChange: (String) -> Unit,
    onSelectExisting: (com.bizarreelectronics.crm.data.remote.dto.CustomerListItem) -> Unit,
    onSelectWalkIn: () -> Unit,
    onCreateNew: (firstName: String, lastName: String?, phone: String?, email: String?) -> Unit,
    onDismiss: () -> Unit,
) {
    var mode by remember { mutableStateOf(PickerMode.ROOT) }
    var newFirst by remember { mutableStateOf("") }
    var newLast by remember { mutableStateOf("") }
    var newPhone by remember { mutableStateOf("") }
    var newEmail by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                when (mode) {
                    PickerMode.ROOT   -> "Add customer to cart"
                    PickerMode.SEARCH -> "Search customers"
                    PickerMode.NEW    -> "Create new customer"
                }
            )
        },
        text = {
            when (mode) {
                PickerMode.ROOT -> PickerRoot(
                    onSearch = { mode = PickerMode.SEARCH },
                    onNew = { mode = PickerMode.NEW },
                    onWalkIn = { onSelectWalkIn(); onDismiss() },
                )
                PickerMode.SEARCH -> PickerSearch(
                    query = searchQuery,
                    results = searchResults,
                    loading = searchLoading,
                    onQueryChange = onSearchQueryChange,
                    onSelect = { onSelectExisting(it); onDismiss() },
                )
                PickerMode.NEW -> PickerNew(
                    firstName = newFirst,
                    lastName = newLast,
                    phone = newPhone,
                    email = newEmail,
                    onFirstName = { newFirst = it },
                    onLastName = { newLast = it },
                    onPhone = { newPhone = it },
                    onEmail = { newEmail = it },
                )
            }
        },
        confirmButton = {
            when (mode) {
                PickerMode.NEW -> TextButton(
                    onClick = {
                        if (newFirst.isNotBlank()) {
                            onCreateNew(newFirst, newLast, newPhone, newEmail)
                            onDismiss()
                        }
                    },
                    enabled = newFirst.isNotBlank(),
                ) { Text("Create & attach") }
                else -> TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        },
        dismissButton = {
            if (mode != PickerMode.ROOT) {
                TextButton(onClick = { mode = PickerMode.ROOT }) { Text("Back") }
            }
        },
    )
}

private enum class PickerMode { ROOT, SEARCH, NEW }

@Composable
private fun PickerRoot(
    onSearch: () -> Unit,
    onNew: () -> Unit,
    onWalkIn: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Solid tile — search existing
        OutlinedCard(
            onClick = onSearch,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Default.Person, contentDescription = null)
                Column {
                    Text("Search existing customer", style = MaterialTheme.typography.titleSmall)
                    Text("Name, phone, or email", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        // Solid tile — create new
        OutlinedCard(
            onClick = onNew,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Default.PersonAdd, contentDescription = null)
                Column {
                    Text("Create new customer", style = MaterialTheme.typography.titleSmall)
                    Text("First name required; rest optional", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        // Ghost tile — walk-in (dashed border)
        androidx.compose.material3.Surface(
            onClick = onWalkIn,
            modifier = Modifier
                .fillMaxWidth()
                .dashedBorder(
                    strokeWidthDp = 1.5f,
                    gapDp = 6f,
                    dashDp = 6f,
                    color = MaterialTheme.colorScheme.outline,
                    cornerRadiusDp = 12f,
                ),
            color = androidx.compose.ui.graphics.Color.Transparent,
            shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    Icons.Default.Person,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Column {
                    Text(
                        "Walk-in customer",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "No customer record — cash/card sale only",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun PickerSearch(
    query: String,
    results: List<com.bizarreelectronics.crm.data.remote.dto.CustomerListItem>,
    loading: Boolean,
    onQueryChange: (String) -> Unit,
    onSelect: (com.bizarreelectronics.crm.data.remote.dto.CustomerListItem) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            label = { Text("Search customers…") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        when {
            loading -> {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    Text("Searching…", style = MaterialTheme.typography.bodySmall)
                }
            }
            query.length < 2 -> {
                Text(
                    "Type at least 2 characters",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            results.isEmpty() -> {
                Text(
                    "No matches",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.heightIn(max = 300.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    items(results, key = { it.id }) { item ->
                        val name = listOfNotNull(item.firstName, item.lastName).joinToString(" ").ifBlank {
                            item.organization ?: item.email ?: "#${item.id}"
                        }
                        val subtitle = listOfNotNull(item.phone, item.email).joinToString(" • ")
                        OutlinedCard(
                            onClick = { onSelect(item) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(modifier = Modifier.padding(12.dp)) {
                                Text(name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                                if (subtitle.isNotBlank()) {
                                    Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PickerNew(
    firstName: String,
    lastName: String,
    phone: String,
    email: String,
    onFirstName: (String) -> Unit,
    onLastName: (String) -> Unit,
    onPhone: (String) -> Unit,
    onEmail: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = firstName,
            onValueChange = onFirstName,
            label = { Text("First name *") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = lastName,
            onValueChange = onLastName,
            label = { Text("Last name") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = phone,
            onValueChange = onPhone,
            label = { Text("Phone") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = email,
            onValueChange = onEmail,
            label = { Text("Email") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// Dashed border modifier — used on the Walk-in ghost tile.
private fun Modifier.dashedBorder(
    strokeWidthDp: Float,
    gapDp: Float,
    dashDp: Float,
    color: Color,
    cornerRadiusDp: Float,
): Modifier = this.drawBehind {
    val d = this.density
    val stroke = Stroke(
        width = strokeWidthDp * d,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf(dashDp * d, gapDp * d), 0f),
    )
    val cornerPx = cornerRadiusDp * d
    drawRoundRect(
        color = color,
        cornerRadius = CornerRadius(cornerPx, cornerPx),
        style = stroke,
    )
}

// ─── Cart discount dialog ─────────────────────────────────────────────────────

@Composable
private fun CartDiscountDialog(
    current: Long,
    mode: DiscountMode,
    subtotalCents: Long,
    onApply: (Long, DiscountMode) -> Unit,
    onDismiss: () -> Unit,
) {
    var valueText by remember { mutableStateOf(if (current > 0) String.format(Locale.US, "%.2f", current / 100.0) else "") }
    var discountMode by remember { mutableStateOf(mode) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Cart Discount") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = discountMode == DiscountMode.FLAT,
                        onClick = { discountMode = DiscountMode.FLAT },
                        label = { Text("$ Flat") },
                    )
                    FilterChip(
                        selected = discountMode == DiscountMode.PERCENT,
                        onClick = { discountMode = DiscountMode.PERCENT },
                        label = { Text("% Percent") },
                    )
                }
                OutlinedTextField(
                    value = valueText,
                    onValueChange = { valueText = it },
                    label = { Text(if (discountMode == DiscountMode.FLAT) "Amount ($)" else "Percent (%)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val v = valueText.toDoubleOrNull() ?: 0.0
                val cents = when (discountMode) {
                    DiscountMode.FLAT -> (v * 100).toLong()
                    // For PERCENT mode we store basis points (500 = 5%),
                    // but here we convert: 5.0% → 500 bp → store as cents = subtotal * 5/100
                    DiscountMode.PERCENT -> (subtotalCents * v / 100).toLong()
                }
                onApply(cents, discountMode)
            }) { Text("Apply") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Tip dialog ───────────────────────────────────────────────────────────────

@Composable
private fun TipDialog(
    current: TipConfig,
    subtotalCents: Long,
    onApply: (TipConfig) -> Unit,
    onDismiss: () -> Unit,
) {
    var valueText by remember { mutableStateOf(if (current.value > 0) String.format(Locale.US, "%.2f", current.value / 100.0) else "") }
    var tipMode by remember { mutableStateOf(current.mode) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Tip") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = tipMode == DiscountMode.FLAT, onClick = { tipMode = DiscountMode.FLAT }, label = { Text("$ Flat") })
                    FilterChip(selected = tipMode == DiscountMode.PERCENT, onClick = { tipMode = DiscountMode.PERCENT }, label = { Text("% Percent") })
                }
                // Preset buttons
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(10, 15, 18, 20).forEach { pct ->
                        SuggestionChip(
                            onClick = {
                                tipMode = DiscountMode.PERCENT
                                valueText = "$pct"
                            },
                            label = { Text("$pct%") },
                        )
                    }
                }
                OutlinedTextField(
                    value = valueText,
                    onValueChange = { valueText = it },
                    label = { Text(if (tipMode == DiscountMode.FLAT) "Amount ($)" else "Percent (%)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val v = valueText.toDoubleOrNull() ?: 0.0
                val valueCents = when (tipMode) {
                    DiscountMode.FLAT -> (v * 100).toLong()
                    DiscountMode.PERCENT -> (subtotalCents * v / 100).toLong()
                }
                onApply(TipConfig(enabled = valueCents > 0, mode = tipMode, value = valueCents))
            }) { Text("Apply") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
