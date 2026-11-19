package com.example.kavasam_alert

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat

/**
 * Lets the user choose which SIM sends the automatic emergency SMS.
 * The choice is saved by the Flutter Settings screen (key sms_sim_sub_id);
 * -1 / missing / SIM removed = the phone's default SIM (the old behaviour).
 */
object SimSms {
    private fun chosenSubId(c: Context): Int =
        c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getLong("flutter.sms_sim_sub_id", -1L).toInt()

    /** Active SIMs: [{subId, slot (1-based), name}] - needs the Phone permission. */
    fun list(c: Context): List<Map<String, Any>> {
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED) return emptyList()
        return try {
            val sm = c.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                ?: return emptyList()
            (sm.activeSubscriptionInfoList ?: emptyList()).map {
                mapOf<String, Any>(
                    "subId" to it.subscriptionId,
                    "slot" to (it.simSlotIndex + 1),
                    "name" to (it.displayName?.toString() ?: (it.carrierName?.toString() ?: ""))
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    @Suppress("DEPRECATION")
    private fun defaultManager(c: Context): SmsManager? =
        if (Build.VERSION.SDK_INT >= 31) c.getSystemService(SmsManager::class.java)
        else SmsManager.getDefault()

    /** SmsManager for the chosen SIM (falls back to the default SIM). */
    @Suppress("DEPRECATION")
    fun manager(c: Context): SmsManager? {
        val sub = chosenSubId(c)
        if (sub >= 0 && list(c).any { (it["subId"] as Int) == sub }) {
            try {
                val sm = if (Build.VERSION.SDK_INT >= 31)
                    c.getSystemService(SmsManager::class.java)?.createForSubscriptionId(sub)
                else SmsManager.getSmsManagerForSubscriptionId(sub)
                if (sm != null) return sm
            } catch (_: Exception) {
            }
        }
        return defaultManager(c)
    }
}
