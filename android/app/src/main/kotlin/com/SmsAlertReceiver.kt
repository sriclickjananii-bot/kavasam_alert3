package com.example.kavasam_alert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Emergency contact's phone: when the tagged SOS SMS arrives, raise the same
 * alert. If the background watcher is running it plays the looping alarm and
 * opens the full-screen alert; otherwise this receiver posts a high-priority
 * full-screen notification that loops the alarm sound by itself.
 */
class SmsAlertReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val msgs = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val body = msgs.joinToString("") { it.messageBody ?: "" }
        if (!body.contains("KAVASAM-SOS")) return

        // First line: "KAVASAM-SOS|<victim name>"
        val name = Regex("""KAVASAM-SOS\|([^\r\n]*)""").find(body)?.groupValues?.get(1)?.trim() ?: ""
        val m = Regex("""q=(-?\d+\.\d+),(-?\d+\.\d+)""").find(body)
        val hasLoc = m != null
        // "Ref:<alertId>" lets this phone tell the responder network that a contact is acting.
        val ref = Regex("""Ref:([A-Za-z0-9_\-]+)""").find(body)?.groupValues?.get(1) ?: ""
        val lat = m?.groupValues?.get(1)?.toDouble() ?: 0.0
        val lon = m?.groupValues?.get(2)?.toDouble() ?: 0.0

        // Watcher running -> it handles everything (looping alarm + launch).
        val svc = BleWatchService.instance
        if (svc != null) {
            svc.onSmsSos(name, hasLoc, lat, lon, ref)
            return
        }

        // Fallback: no service needed.
        BleWatchService.pendingSos = hashMapOf<String, Any?>(
            "name" to name, "lat" to lat, "lon" to lon, "hasLocation" to hasLoc,
            "numbers" to ArrayList<String>(), "sent" to ArrayList<String>(),
            "failed" to ArrayList<String>(), "fromSms" to true, "ref" to ref
        )
        AlertNotifier.post(
            context,
            if (name.isEmpty()) "\uD83D\uDEA8 SOS ALERT — someone you know needs help!" else "\uD83D\uDEA8 $name is in danger!",
            "Tap to see the location and call Police"
        )

        // Speak "<name> is in danger" (keep the receiver alive until done).
        val pr = goAsync()
        val finished = java.util.concurrent.atomic.AtomicBoolean(false)
        fun finish() {
            if (finished.compareAndSet(false, true)) pr.finish()
        }
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ finish() }, 12_000)
        VoiceAlert.speak(
            context,
            if (name.isEmpty()) "Someone you know is in danger. Please help." else "$name is in danger. Please help.",
            null
        ) { finish() }
    }
}