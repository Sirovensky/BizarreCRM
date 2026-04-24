package com.bizarreelectronics.crm.util

import android.app.Activity
import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.view.Display
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §16.11 — Secondary display manager for customer-facing POS display.
 *
 * When an external display is connected (e.g. via HDMI/USB-C), opens a
 * [Presentation] window showing cart totals, an ad slot, and a signature
 * capture stub.
 *
 * API 17+ required for [Presentation]. Gated by [Build.VERSION.SDK_INT].
 *
 * Usage:
 *   1. Call [attach] from the Activity's onResume / after cart changes.
 *   2. Call [updateCart] whenever cart state changes.
 *   3. Call [detach] from onPause / onDestroy.
 *
 * [PosCustomerDisplayPresentation] is the Presentation subclass that renders
 * the customer-facing Compose UI.
 *
 * Signature capture: [PosSignatureCaptureScreen] — stub composable; deferred.
 */
@Singleton
class CustomerDisplayManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    private var presentation: PosCustomerDisplayPresentation? = null
    private var _currentCart: PosCartState? = null

    /** Attach to the first available external display. No-op if API < 17 or no display. */
    fun attach(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1) return

        val displayManager = activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
            ?: return

        val externalDisplay = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .firstOrNull() ?: return

        val existing = presentation
        if (existing != null && existing.display == externalDisplay && existing.isShowing) {
            // Already showing on this display — just update cart
            _currentCart?.let { existing.updateCart(it) }
            return
        }

        // Dismiss stale presentation if display changed
        existing?.dismiss()

        val p = PosCustomerDisplayPresentation(activity, externalDisplay)
        _currentCart?.let { p.setInitialCart(it) }
        runCatching { p.show() }
        presentation = p
    }

    /** Update cart data on the secondary display. Safe to call when no display is attached. */
    fun updateCart(cart: PosCartState) {
        _currentCart = cart
        presentation?.updateCart(cart)
    }

    /** Detach and dismiss the presentation. Call from onPause. */
    fun detach() {
        presentation?.dismiss()
        presentation = null
    }

    val isActive: Boolean get() = presentation?.isShowing == true
}

// ─── Presentation ─────────────────────────────────────────────────────────────

/**
 * Customer-facing secondary display window.
 * Renders cart totals + store branding + ad slot + signature stub.
 */
class PosCustomerDisplayPresentation(
    context: Context,
    display: Display,
) : Presentation(context, display) {

    private var cartState = mutableStateOf<PosCartState?>(null)

    fun setInitialCart(cart: PosCartState) {
        cartState.value = cart
    }

    fun updateCart(cart: PosCartState) {
        cartState.value = cart
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val view = ComposeView(context).apply {
            setContent {
                val cart by cartState
                MaterialTheme {
                    CustomerDisplayContent(cart = cart)
                }
            }
        }
        setContentView(view)
    }
}

// ─── Customer display composable ─────────────────────────────────────────────

@Composable
private fun CustomerDisplayContent(cart: PosCartState?) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF1A1A2E)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.padding(32.dp),
        ) {
            // Store branding
            Text(
                text = "Bizarre Electronics",
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )

            if (cart == null || cart.lines.isEmpty()) {
                Text(
                    text = "Welcome!",
                    fontSize = 48.sp,
                    color = Color.White.copy(alpha = 0.7f),
                )
            } else {
                // Line items
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (line in cart.lines) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = "${line.name} x${line.qty}",
                                color = Color.White,
                                fontSize = 18.sp,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                text = line.totalCents.formatAsMoney(),
                                color = Color.White,
                                fontSize = 18.sp,
                            )
                        }
                    }
                }

                Divider(color = Color.White.copy(alpha = 0.3f))

                // Total
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("TOTAL", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Text(
                        cart.totalCents.formatAsMoney(),
                        color = Color(0xFF4ECDC4),
                        fontSize = 36.sp,
                        fontWeight = FontWeight.ExtraBold,
                    )
                }

                // Signature capture stub (deferred)
                PosSignatureCaptureScreen()
            }

            // Ad slot
            Spacer(Modifier.height(32.dp))
            Text(
                text = "Thank you for choosing us!",
                fontSize = 16.sp,
                color = Color.White.copy(alpha = 0.5f),
            )
        }
    }
}

// ─── Signature capture stub ──────────────────────────────────────────────────

/**
 * Stub composable for signature capture on the secondary display.
 * Full implementation deferred (requires touch event routing from
 * secondary display surface to the primary app process).
 */
@Composable
fun PosSignatureCaptureScreen() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(120.dp)
            .background(Color.White.copy(alpha = 0.1f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "Signature capture — coming soon",
            color = Color.White.copy(alpha = 0.4f),
            fontSize = 14.sp,
        )
    }
}
