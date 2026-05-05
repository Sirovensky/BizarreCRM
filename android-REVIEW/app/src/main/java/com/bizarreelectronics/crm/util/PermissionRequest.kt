package com.bizarreelectronics.crm.util

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.State
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat

/**
 * §13.2 POST_NOTIFICATIONS runtime permission helper.
 *
 * Android 13 (API 33) requires an explicit runtime grant before the system
 * will show ANY notifications from the app — including FCM push. Apps that
 * silently assume the permission end up invisible on new installs.
 *
 * This helper exposes a Composable that:
 *   - Returns the current grant state as a State<Boolean>.
 *   - Fires the system prompt at most once automatically (on first mount).
 *   - Re-checks on resume so a Settings-app toggle is reflected immediately.
 *
 * Pre-Android-13 devices always return true — the permission didn't exist.
 */
@Composable
fun rememberNotificationPermission(autoRequest: Boolean = true): State<Boolean> {
    val context = LocalContext.current
    val granted = remember { mutableStateOf(isNotificationPermissionGranted(context)) }

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { result ->
        granted.value = result
    }

    LaunchedEffect(Unit) {
        if (!autoRequest) return@LaunchedEffect
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return@LaunchedEffect
        if (!granted.value) {
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // Re-check on resume so a trip to system Settings is reflected when the
    // user returns. DisposableEffect is cheaper than LifecycleObserver here
    // because the composable only needs the ON_RESUME signal and no cleanup.
    DisposableEffect(context) {
        val callback = Runnable { granted.value = isNotificationPermissionGranted(context) }
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.postDelayed(callback, 300)
        onDispose { handler.removeCallbacks(callback) }
    }

    return granted
}

fun isNotificationPermissionGranted(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
    return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.POST_NOTIFICATIONS,
    ) == PackageManager.PERMISSION_GRANTED
}
