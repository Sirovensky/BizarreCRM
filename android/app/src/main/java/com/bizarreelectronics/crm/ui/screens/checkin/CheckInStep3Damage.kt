package com.bizarreelectronics.crm.ui.screens.checkin

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ButtonGroup
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val ACCESSORY_OPTIONS = listOf("SIM tray", "Case", "Tempered glass", "Charger", "Cable")

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CheckInStep3Damage(
    markers: List<DamageMarker>,
    activeSide: DeviceSide,
    condition: DeviceCondition,
    includes: Set<String>,
    ldiStatus: LdiStatus,
    onAddMarker: (DamageMarker) -> Unit,
    onRemoveMarker: (DamageMarker) -> Unit,
    onSideChange: (DeviceSide) -> Unit,
    onConditionChange: (DeviceCondition) -> Unit,
    onToggleAccessory: (String) -> Unit,
    onLdiChange: (LdiStatus) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item(key = "hint") {
            Text(
                "Tap to mark pre-existing damage — these are NOT what we're fixing",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }

        item(key = "side_tabs") {
            PrimaryTabRow(selectedTabIndex = DeviceSide.entries.indexOf(activeSide)) {
                DeviceSide.entries.forEach { side ->
                    Tab(
                        selected = activeSide == side,
                        onClick = { onSideChange(side) },
                        text = { Text(side.label) },
                        modifier = Modifier.semantics {
                            contentDescription = "Show ${side.label} of device"
                        },
                    )
                }
            }
        }

        item(key = "device_outline") {
            var activeDamageType by remember { mutableStateOf(DamageType.CRACK) }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                DamageTypeSelector(
                    active = activeDamageType,
                    onSelect = { activeDamageType = it },
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
                DeviceOutlineCanvas(
                    side = activeSide,
                    markers = markers.filter { it.side == activeSide },
                    activeDamageType = activeDamageType,
                    onTap = { xFrac, yFrac ->
                        onAddMarker(DamageMarker(activeSide, xFrac, yFrac, activeDamageType))
                    },
                    onLongPress = { marker -> onRemoveMarker(marker) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                )
                Text(
                    "Long-press a marker to remove it",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        item(key = "condition_chips") {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("Overall condition", style = MaterialTheme.typography.titleSmall)
                // M3 Expressive: ButtonGroup segmented single-select. Condition
                // has a natural ordering (Mint → Salvage) that maps to
                // segmented semantics better than free-floating FilterChips.
                @OptIn(ExperimentalMaterial3ExpressiveApi::class)
                ButtonGroup(
                    overflowIndicator = { /* fixed 5 items; no overflow */ },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    DeviceCondition.entries.forEach { c ->
                        toggleableItem(
                            checked = condition == c,
                            onCheckedChange = { checked -> if (checked) onConditionChange(c) },
                            label = c.label,
                        )
                    }
                }
            }
        }

        item(key = "includes_chips") {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("Includes", style = MaterialTheme.typography.titleSmall)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ACCESSORY_OPTIONS.forEach { item ->
                        FilterChip(
                            selected = item in includes,
                            onClick = { onToggleAccessory(item) },
                            label = { Text(item) },
                            modifier = Modifier.semantics {
                                contentDescription = "Accessory included: $item"
                            },
                        )
                    }
                }
            }
        }

        item(key = "ldi_card") {
            LdiCard(
                status = ldiStatus,
                onStatusChange = onLdiChange,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DamageTypeSelector(
    active: DamageType,
    onSelect: (DamageType) -> Unit,
    modifier: Modifier = Modifier,
) {
    FlowRow(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        DamageType.entries.forEach { type ->
            FilterChip(
                selected = active == type,
                onClick = { onSelect(type) },
                label = { Text("${type.symbol} ${type.name.lowercase().replaceFirstChar { it.uppercase() }}") },
                modifier = Modifier.semantics {
                    contentDescription = "Damage type: ${type.name}"
                },
            )
        }
    }
}

@Composable
private fun DeviceOutlineCanvas(
    side: DeviceSide,
    markers: List<DamageMarker>,
    activeDamageType: DamageType,
    onTap: (xFrac: Float, yFrac: Float) -> Unit,
    onLongPress: (DamageMarker) -> Unit,
    modifier: Modifier = Modifier,
) {
    val textMeasurer = rememberTextMeasurer()
    val outlineColor = MaterialTheme.colorScheme.outline
    val primaryColor = MaterialTheme.colorScheme.primary

    Box(
        modifier = modifier
            .aspectRatio(0.46f)
            .pointerInput(side, activeDamageType) {
                detectTapGestures(
                    onTap = { offset ->
                        onTap(offset.x / size.width, offset.y / size.height)
                    },
                    onLongPress = { offset ->
                        val hitRadius = 40f
                        val hit = markers.firstOrNull { m ->
                            val mx = m.xFraction * size.width
                            val my = m.yFraction * size.height
                            val dx = mx - offset.x
                            val dy = my - offset.y
                            dx * dx + dy * dy < hitRadius * hitRadius
                        }
                        if (hit != null) onLongPress(hit)
                    },
                )
            }
            .semantics {
                contentDescription = "Device diagram for ${side.label}. Tap to add damage marker. Long-press marker to remove."
            },
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            drawDeviceOutline(outlineColor)
            markers.forEach { marker ->
                val px = marker.xFraction * size.width
                val py = marker.yFraction * size.height
                val markerColor = when (marker.type.colorToken) {
                    "error" -> Color(0xFFE2526C)
                    "warning" -> Color(0xFFE8A33D)
                    "teal" -> Color(0xFF4DB8C9)
                    else -> primaryColor
                }
                drawCircle(color = markerColor, radius = 14f, center = Offset(px, py))
                drawText(
                    textMeasurer = textMeasurer,
                    text = marker.type.symbol,
                    topLeft = Offset(px - 8f, py - 10f),
                    style = androidx.compose.ui.text.TextStyle(
                        color = Color.White,
                        fontSize = 12.sp,
                    ),
                )
            }
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawDeviceOutline(color: Color) {
    val cornerRadius = 28.dp.toPx()
    val w = size.width
    val h = size.height
    val stroke = Stroke(width = 2.dp.toPx())

    val path = Path().apply {
        moveTo(cornerRadius, 0f)
        lineTo(w - cornerRadius, 0f)
        quadraticTo(w, 0f, w, cornerRadius)
        lineTo(w, h - cornerRadius)
        quadraticTo(w, h, w - cornerRadius, h)
        lineTo(cornerRadius, h)
        quadraticTo(0f, h, 0f, h - cornerRadius)
        lineTo(0f, cornerRadius)
        quadraticTo(0f, 0f, cornerRadius, 0f)
        close()
    }
    drawPath(path, color = color, style = stroke)

    // Camera notch hint at top
    drawRoundRect(
        color = color,
        topLeft = Offset(w * 0.38f, 6.dp.toPx()),
        size = androidx.compose.ui.geometry.Size(w * 0.24f, 8.dp.toPx()),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(4.dp.toPx()),
        style = stroke,
    )

    // Home indicator hint at bottom
    drawRoundRect(
        color = color,
        topLeft = Offset(w * 0.35f, h - 16.dp.toPx()),
        size = androidx.compose.ui.geometry.Size(w * 0.30f, 4.dp.toPx()),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun LdiCard(
    status: LdiStatus,
    onStatusChange: (LdiStatus) -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = when (status) {
                LdiStatus.TRIPPED -> MaterialTheme.colorScheme.errorContainer
                LdiStatus.CLEAN -> MaterialTheme.colorScheme.secondaryContainer
                LdiStatus.NOT_TESTED -> MaterialTheme.colorScheme.surfaceVariant
            },
        ),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("Liquid Damage Indicator (LDI)", style = MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LdiStatus.entries.forEach { s ->
                    FilterChip(
                        selected = status == s,
                        onClick = { onStatusChange(s) },
                        label = { Text(s.label) },
                        modifier = Modifier.semantics {
                            contentDescription = "LDI status: ${s.label}"
                        },
                    )
                }
            }
        }
    }
}
