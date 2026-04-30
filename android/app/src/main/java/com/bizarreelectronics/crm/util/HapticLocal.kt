package com.bizarreelectronics.crm.util

import androidx.compose.runtime.staticCompositionLocalOf

/**
 * CompositionLocal carrying the app-wide [HapticFeedback] helper. Provided
 * from MainActivity via Hilt so composables can fire haptics without having
 * to thread the singleton through every call site.
 *
 * Usage:
 * ```
 * val haptic = LocalAppHaptic.current
 * Button(onClick = {
 *     haptic?.fire(HapticKind.Tick)
 *     onClick()
 * }) { ... }
 * ```
 *
 * The pref-gate (hapticEnabled) lives inside [HapticFeedback.fire] — callers
 * never check the toggle themselves.
 */
val LocalAppHaptic = staticCompositionLocalOf<HapticFeedback?> { null }

/**
 * CompositionLocal carrying the app-wide [HapticController] for §69 catalog events.
 * Provided from MainActivity alongside [LocalAppHaptic] so composables can fire
 * the extended haptic catalog without threading the singleton through every call site.
 *
 * Usage:
 * ```kotlin
 * val hapticCtrl = LocalAppHapticController.current
 * Switch(
 *     checked = on,
 *     onCheckedChange = { v ->
 *         hapticCtrl?.fire(HapticEvent.ToggleChange)
 *         onToggle(v)
 *     },
 * )
 * ```
 *
 * All system-setting gates (HAPTIC_FEEDBACK_ENABLED, quiet mode, in-app toggle)
 * are enforced inside [HapticController.fire] — callers never check them directly.
 */
val LocalAppHapticController = staticCompositionLocalOf<HapticController?> { null }
