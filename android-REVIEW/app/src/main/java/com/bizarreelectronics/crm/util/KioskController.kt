package com.bizarreelectronics.crm.util

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.view.KeyEvent
import android.view.Window
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §57.1 Kiosk / Lock-Task Mode controller.
 *
 * Wraps [Activity.startLockTask] / [Activity.stopLockTask] so all lock-task
 * lifecycle is isolated from composable code.
 *
 * ## Device-owner requirement
 * [startLockTask] works for any app if the user manually pins the screen via
 * Settings → Security → Screen pinning.  Programmatic, un-dismissable lock-task
 * (which also disables the status bar and notification shade) requires the app
 * to be granted Device Owner status via `dpm set-device-owner` or an MDM
 * enrollment.  When the app is NOT a Device Owner the system still enters
 * lock-task mode but displays a toast notifying the user they can exit with
 * the standard Back + Recents gesture.
 *
 * See §57.4 NOTE-defer for hardware-key suppression limitations.
 */
@Singleton
class KioskController @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    /** Whether the process is currently inside a lock-task session. */
    val isLocked: Boolean
        get() {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
            } else {
                @Suppress("DEPRECATION")
                am.isInLockTaskMode
            }
        }

    /**
     * Enter lock-task mode for the given [activity].
     *
     * When the app is a Device Owner the system enters fully locked mode (status
     * bar hidden, Home/Recents suppressed).  Without Device Owner the system
     * shows a "Screen is pinned" toast and the user can exit with Back + Recents.
     */
    fun enterLockTask(activity: Activity) {
        if (!isLocked) {
            activity.startLockTask()
        }
    }

    /**
     * Exit lock-task mode for the given [activity].
     *
     * Only callable from the app that started lock-task.  Will throw if the
     * caller is not the lock-task owner.
     */
    fun exitLockTask(activity: Activity) {
        if (isLocked) {
            activity.stopLockTask()
        }
    }

    /**
     * §57.4 — Intercept volume-key events at the Activity level.
     *
     * Call from [Activity.onKeyDown] / [Activity.onKeyUp].  Returns `true`
     * (consumed) for VOLUME_UP, VOLUME_DOWN, and POWER while in kiosk mode,
     * preventing volume or sleep.
     *
     * Note: POWER-button suppression is only effective when the app is a Device
     * Owner.  Without Device Owner the power button always works (OS limitation).
     * See §57.4 NOTE-defer.
     */
    fun onKeyEvent(keyCode: Int): Boolean {
        if (!isLocked) return false
        return keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
            keyCode == KeyEvent.KEYCODE_POWER
    }

    /**
     * §57.4 — Apply window flags that keep the screen awake while in kiosk mode.
     * Call once from [Activity.onResume] when entering kiosk mode; clear flags
     * with [clearWakeFlags] on exit.
     */
    @Suppress("DEPRECATION")
    fun applyWakeFlags(window: Window) {
        window.addFlags(
            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
        )
    }

    /** Remove wake flags applied by [applyWakeFlags]. */
    @Suppress("DEPRECATION")
    fun clearWakeFlags(window: Window) {
        window.clearFlags(
            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
        )
    }
}
