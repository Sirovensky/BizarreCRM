package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddShoppingCart
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.rememberReduceMotion
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * §16.8 — Full-screen success overlay shown after a completed POS sale.
 *
 * Features:
 *  - 30-particle spring-physics confetti (ReduceMotion → static 🎉 emoji).
 *  - Big total display.
 *  - Action buttons: Print, Email, SMS, New Sale.
 *  - Auto-dismiss after 10 s or immediate tap of "New Sale".
 */
@Composable
fun PosSuccessScreen(
    cart: PosCartState,
    invoiceId: Long,
    serverBaseUrl: String,
    appPreferences: AppPreferences,
    onNewSale: () -> Unit,
    onSmsSend: suspend (phone: String, body: String) -> Result<Unit>,
    cashDrawerController: CashDrawerControllerStub? = null,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = rememberReduceMotion(appPreferences)

    // Auto-dismiss after 10 s
    LaunchedEffect(Unit) {
        delay(10_000L)
        onNewSale()
    }

    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        // Background
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.95f),
        ) {}

        // Confetti layer
        if (!reduceMotion) {
            ConfettiLayer(modifier = Modifier.fillMaxSize())
        }

        // Content card
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier
                .padding(32.dp)
                .semantics { contentDescription = "Sale complete" },
        ) {
            Text(
                text = if (reduceMotion) "🎉" else "Sale Complete!",
                fontSize = 48.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )

            // Big total
            Text(
                text = cart.totalCents.formatAsMoney(),
                fontSize = 56.sp,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.semantics {
                    contentDescription = "Total charged: ${cart.totalCents.formatAsMoney()}"
                },
            )

            Text(
                text = "Invoice #$invoiceId",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
            )

            // Receipt actions
            PosReceiptActions(
                cart = cart,
                invoiceId = invoiceId,
                serverBaseUrl = serverBaseUrl,
                onSmsSend = onSmsSend,
                cashDrawerController = cashDrawerController,
                modifier = Modifier.fillMaxWidth(),
            )

            // New Sale button
            Button(
                onClick = onNewSale,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                ),
            ) {
                Icon(Icons.Default.AddShoppingCart, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("New Sale", style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

// ─── Confetti ─────────────────────────────────────────────────────────────────

private data class Particle(
    val x: Float,
    val y: Float,
    val vx: Float,
    val vy: Float,
    val color: Color,
    val size: Float,
    val angle: Float,
    val spin: Float,
)

private val CONFETTI_COLORS = listOf(
    Color(0xFFFF6B6B), Color(0xFF4ECDC4), Color(0xFF45B7D1),
    Color(0xFFFFA07A), Color(0xFF98D8C8), Color(0xFFFFD700),
    Color(0xFFDDA0DD), Color(0xFF90EE90),
)

@Composable
private fun ConfettiLayer(modifier: Modifier = Modifier) {
    val particles = remember {
        List(30) { _ ->
            Particle(
                x = Random.nextFloat(),
                y = -Random.nextFloat() * 0.3f,
                vx = (Random.nextFloat() - 0.5f) * 0.008f,
                vy = 0.003f + Random.nextFloat() * 0.005f,
                color = CONFETTI_COLORS.random(),
                size = 8f + Random.nextFloat() * 12f,
                angle = Random.nextFloat() * 360f,
                spin = (Random.nextFloat() - 0.5f) * 4f,
            )
        }
    }

    val infiniteTransition = rememberInfiniteTransition(label = "confetti")
    val tick by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1000f,
        animationSpec = infiniteRepeatable(
            animation = tween(10_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "confetti_tick",
    )

    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val t = tick

        for (p in particles) {
            val px = ((p.x + p.vx * t) % 1f) * w
            val py = ((p.y + p.vy * t) % 1.2f) * h
            val currentAngle = (p.angle + p.spin * t) * Math.PI.toFloat() / 180f

            val rotatedX = px + p.size * cos(currentAngle)
            val rotatedY = py + p.size * sin(currentAngle)

            drawCircle(
                color = p.color,
                radius = p.size / 2f,
                center = Offset(px, py),
            )
        }
    }
}
