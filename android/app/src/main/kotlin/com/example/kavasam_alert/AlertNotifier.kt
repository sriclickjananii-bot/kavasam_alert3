package com.example.kavasam_alert

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat

/** Fallback alert (used when the background service is not running, e.g. SMS received). */
object AlertNotifier {
    private const val CH = "kavasam_sms_alert"
    private const val ID = 4103

    fun post(ctx: Context, title: String, text: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val sound = Uri.parse("android.resource://${ctx.packageName}/${R.raw.sos_alarm}")
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CH, "SOS (SMS) alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(
                    sound,
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                )
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }
        val launch = Intent(ctx, MainActivity::class.java).apply {
            action = BleWatchService.ACTION_SOS
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pi = PendingIntent.getActivity(ctx, 2, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(ctx, CH)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title).setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pi, true).setContentIntent(pi)
            .setSound(sound).setOngoing(true).setAutoCancel(false)
            .build()
        n.flags = n.flags or Notification.FLAG_INSISTENT      // keeps the sound looping
        nm.notify(ID, n)
    }
}
