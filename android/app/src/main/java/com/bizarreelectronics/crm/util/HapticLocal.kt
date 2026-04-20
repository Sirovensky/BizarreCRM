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
