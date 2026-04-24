package com.bizarreelectronics.crm.service

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.bizarreelectronics.crm.BizarreCrmApp
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.R
import timber.log.Timber
import java.util.concurrent.atomic.AtomicInteger

/**
 * §13 L1594 — Android 16 Live Update stub.
 *
 * Live Updates (Android 16 / API 36) allow a notification to display an
 * ongoing progress bar anchored in the status-bar / lock-screen while a
 * background operation is running (e.g. an overdue invoice approaching SLA
 * breach, or a repair in-progress with elapsed-time ticker).
 *
 * Current state (stub):
 * ─────────────────────
 * [NotificationCompat.ProgressStyle] was introduced in AndroidX Core 1.16.0
 * and targets API 36 behaviour.  The style is available via the compat layer
 * so it compiles against minSdk 26, but the enhanced lock-screen rendering is
 * only visible on Android 16+ devices; older devices fall back to a standard
 * indeterminate progress bar inside the notification shade.
 *
 * Wiring:
 * ───────
 * Feature screens that need Live Updates (e.g. RepairInProgressService,
 * InvoiceOverdueChecker) call [showLiveUpdate] passing the contextual title,
 * a short progress label (e.g. "2 h 14 m overdue"), and the deep-link
 * navigate_to string so tapping opens the relevant screen.  Call
 * [cancelLiveUpdate] with the returned ID when the condition clears.
 *
 * The notification is posted on the [BizarreCrmApp.CH_SLA_BREACH] channel so
 * it inherits the critical vibration pattern and badge.  Callers may pass a
 * different [channelId] for non-SLA contexts (e.g. background sync progress
 * on [BizarreCrmApp.CH_SYNC]).
 *
 * Future work:
 * ────────────
 * Once Android 16 is a stable targetSdk, wire [NotificationCompat.ProgressStyle]
 * with `setProgressText()`, `setProgressTrackerIcon()`, and the new
 * `setProgressSegments()` API for multi-stage repair progress.
 */
object LiveUpdateNotifier {

    private const val TAG = "LiveUpdateNotifier"
    private val idCounter = AtomicInteger(50_000)

    /**
     * Post or update a Live Update notification.
     *
     * @param context     Application or service context.
     * @param title       Primary notification title (e.g. "Invoice #1042 overdue").
     * @param progressText Short label shown in the progress row (e.g. "2 h 14 m overdue").
     * @param deepLink    navigate_to string for MainActivity deep-link on tap
     *                    (e.g. "invoices/1042").
     * @param channelId   Channel to post on. Defaults to [BizarreCrmApp.CH_SLA_BREACH].
     * @param existingId  If non-null, update the notification with this ID instead of
     *                    allocating a new one. Pass the value returned by a previous
     *                    [showLiveUpdate] call to avoid creating duplicate entries.
     * @return            The notification ID used. Store it to pass back as [existingId]
     *                    on subsequent updates and to [cancelLiveUpdate] on completion.
     */
    fun showLiveUpdate(
        context: Context,
        title: String,
        progressText: String,
        deepLink: String? = null,
        channelId: String = BizarreCrmApp.CH_SLA_BREACH,
        existingId: Int? = null,
    ): Int {
        val id = existingId ?: idCounter.getAndIncrement()

        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            if (!deepLink.isNullOrBlank()) putExtra("navigate_to", deepLink)
        }
        val tapPending = PendingIntent.getActivity(
            context, id, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // §13 L1594 — NotificationCompat.ProgressStyle is the Android 16 / API 36
        // Live Updates API (AndroidX Core 1.16.0+).  Current dependency is Core 1.15.0
        // which does not expose ProgressStyle yet.  We build a compatible stub using
        // standard indeterminate-progress + BigTextStyle that gives equivalent UX on
        // all current targets.  Once Core is bumped to 1.16.0, replace setStyle() with:
        //
        //   .setStyle(
        //       NotificationCompat.ProgressStyle()
        //           .setProgressText(progressText)
        //           .setStyledByProgress(false)
        //   )
        //
        // and remove .setProgress(0, 0, true) (ProgressStyle manages the bar itself).
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(progressText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(tapPending)
            .setStyle(NotificationCompat.BigTextStyle().bigText(progressText))
            .setProgress(0, 0, /* indeterminate */ true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        runCatching {
            NotificationManagerCompat.from(context).notify(id, notification)
        }.onFailure { e ->
            Timber.w(e, "%s: failed to post live update id=%d (likely missing POST_NOTIFICATIONS)", TAG, id)
        }

        Timber.d("%s: showLiveUpdate id=%d title=%s", TAG, id, title)
        return id
    }

    /**
     * Cancel a Live Update notification previously posted by [showLiveUpdate].
     *
     * Call this when the underlying condition clears (e.g. invoice is paid,
     * SLA breach is resolved, repair moves to "completed" status).
     *
     * @param context Application or service context.
     * @param id      The notification ID returned by [showLiveUpdate].
     */
    fun cancelLiveUpdate(context: Context, id: Int) {
        NotificationManagerCompat.from(context).cancel(id)
        Timber.d("%s: cancelled live update id=%d", TAG, id)
    }
}
