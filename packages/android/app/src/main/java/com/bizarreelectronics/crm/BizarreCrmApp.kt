package com.bizarreelectronics.crm

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.bizarreelectronics.crm.data.sync.SyncWorker
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class BizarreCrmApp : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        SyncWorker.schedule(this)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            val channels = listOf(
                NotificationChannel("sms", "SMS Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "New SMS messages from customers"
                },
                NotificationChannel("tickets", "Ticket Updates", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Ticket status changes and assignments"
                },
                NotificationChannel("appointments", "Appointments", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Upcoming appointment reminders"
                },
                NotificationChannel("sync", "Background Sync", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Data synchronization status"
                },
            )

            channels.forEach { manager.createNotificationChannel(it) }
        }
    }
}
