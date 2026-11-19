package com.example.kavasam_alert

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import java.util.Date

/**
 * Free-tier "responder network" (no Cloud Functions, no billing):
 *
 *  - raiseAlertAsync(): the phone that raised the SOS writes one document to Firestore /alerts.
 *  - startListening(): every opted-in phone keeps a Firestore listener on recent alerts and
 *    decides locally whether it is close enough. Phone positions never leave the phone.
 *
 * Who gets alerted (escalation):
 *  - Ring 1 (0-5 km): every opted-in phone within 5 km is alerted at once.
 *  - Ring 2 (5-10 km): opened only if NO emergency contact has responded yet AND either
 *      (a) fewer than 3 phones in ring 1 answered within the first minute, or
 *      (b) 5 minutes passed without an emergency contact responding.
 *    All phones in that next 5 km are then alerted together.
 *  - As soon as an emergency contact responds (taps "I am responding" / calls Police on the
 *    alert screen), ring 2 is never opened.
 *  Answers are stored in /alerts/{id}/responses: "<uid>_ack" (a phone was alerted)
 *  and "<uid>_contact" (an emergency contact responded).
 */
object ResponderNet {
    private const val TAG = "ResponderNet"
    private const val RING1_M = 5000f
    private const val RING2_M = 10000f
    private const val MIN_PHONES = 3
    private const val CHECK_MS = 60_000L
    private const val CONTACT_WAIT_MS = 5 * 60_000L
    private const val LIFETIME_MS = 15 * 60_000L
    private const val TICK_MS = 15_000L

    private fun flutterPrefs(c: Context) =
        c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /** Opt-in switch (Profile & Language screen). */
    fun enabled(c: Context) = flutterPrefs(c).getBoolean("flutter.responder_enabled", false)

    private val handler = Handler(Looper.getMainLooper())
    private var registration: ListenerRegistration? = null
    private var starting = false
    private var myUid: String? = null
    private var service: BleWatchService? = null

    private class Tracked(
        val id: String, val name: String, val lat: Double, val lon: Double,
        val key: String, val seq: Int, val createdMs: Long, var fired: Boolean = false
    ) {
        var ring1Acks = 0
        var contactResponded = false
        var loaded = false
        var reg: ListenerRegistration? = null
    }
    private val tracked = HashMap<String, Tracked>()
    private var ticking = false

    private fun withUid(onReady: (String) -> Unit) {
        val auth = FirebaseAuth.getInstance()
        val u = auth.currentUser
        if (u != null) { onReady(u.uid); return }
        auth.signInAnonymously()
            .addOnSuccessListener { r -> r.user?.let { onReady(it.uid) } }
            .addOnFailureListener { Log.w(TAG, "anonymous sign-in failed", it) }
    }

    // ------------------------------------------------------------- raise

    /** Same SOS = same id for ~10 min (also lets the SMS carry a "Ref:" so contacts can answer). */
    fun makeAlertId(deviceKey: String, seq: Int): String {
        val bucket = System.currentTimeMillis() / 600_000L
        return "${deviceKey}_${seq}_$bucket"
    }

    /** Writes the alert. Firestore queues the write if the phone is offline right now. */
    fun raiseAlertAsync(
        c: Context, deviceKey: String, seq: Int, name: String, lat: Double, lon: Double,
        id: String = makeAlertId(deviceKey, seq)
    ) {
        withUid { uid ->
            val data = hashMapOf<String, Any>(
                "key" to deviceKey, "seq" to seq, "name" to name.take(40),
                "lat" to lat, "lon" to lon, "raisedBy" to uid,
                "createdAt" to FieldValue.serverTimestamp()
            )
            // A second phone reporting the same SOS is rejected by the rules: that's expected.
            FirebaseFirestore.getInstance().collection("alerts").document(id).set(data)
                .addOnFailureListener { Log.d(TAG, "alert not written (duplicate?): ${it.message}") }
        }
    }

    // ------------------------------------------------------------- listen

    fun startListening(svc: BleWatchService) {
        service = svc
        if (registration != null || starting) return
        starting = true
        withUid { uid ->
            myUid = uid
            val since = Timestamp(Date(System.currentTimeMillis() - LIFETIME_MS))
            registration = FirebaseFirestore.getInstance().collection("alerts")
                .whereGreaterThan("createdAt", since)
                .addSnapshotListener { snap, err ->
                    if (err != null || snap == null) { Log.w(TAG, "listen error", err); return@addSnapshotListener }
                    for (ch in snap.documentChanges) {
                        if (ch.type == DocumentChange.Type.ADDED) track(ch.document)
                    }
                }
            starting = false
        }
    }

    fun stopListening() {
        registration?.remove()
        registration = null
        starting = false
        tracked.values.forEach { it.reg?.remove() }
        tracked.clear()
        handler.removeCallbacks(tick)
        ticking = false
    }

    private fun track(d: DocumentSnapshot) {
        if (tracked.containsKey(d.id)) return
        if (d.getString("raisedBy") == myUid) return                  // my own alert
        val lat = d.getDouble("lat") ?: return
        val lon = d.getDouble("lon") ?: return
        val created = d.getTimestamp("createdAt", DocumentSnapshot.ServerTimestampBehavior.ESTIMATE)?.toDate()?.time
            ?: System.currentTimeMillis()
        val t = Tracked(
            d.id, d.getString("name") ?: "", lat, lon,
            d.getString("key") ?: return, (d.getLong("seq") ?: 0L).toInt(), created
        )
        tracked[d.id] = t
        // Follow how many phones answered and whether an emergency contact is already acting.
        t.reg = FirebaseFirestore.getInstance().collection("alerts").document(d.id)
            .collection("responses")
            .addSnapshotListener { snap, err ->
                if (err != null || snap == null) {
                    // Rules not updated yet / offline: treat as "nobody answered".
                    t.loaded = true
                    evaluate()
                    return@addSnapshotListener
                }
                var acks = 0
                var contact = false
                for (r in snap.documents) {
                    when (r.getString("type")) {
                        "ack" -> if ((r.getLong("ring") ?: 1L) == 1L) acks++
                        "contact" -> contact = true
                    }
                }
                t.ring1Acks = acks
                t.contactResponded = contact
                t.loaded = true
                evaluate()
            }
        evaluate()
        if (!ticking) { ticking = true; handler.postDelayed(tick, TICK_MS) }
    }

    private val tick = object : Runnable {
        override fun run() {
            evaluate()
            if (tracked.isNotEmpty()) handler.postDelayed(this, TICK_MS) else ticking = false
        }
    }

    /** Ring 2 (5-10 km) opens only while no emergency contact has responded. */
    private fun ring2Open(t: Tracked, age: Long): Boolean {
        if (t.contactResponded) return false           // an emergency contact is already acting
        if (!t.loaded) return false                    // wait until the answers have been read
        val tooFewPhones = age >= CHECK_MS && t.ring1Acks < MIN_PHONES
        val contactSilent = age >= CONTACT_WAIT_MS
        return tooFewPhones || contactSilent
    }

    private fun sendAck(t: Tracked, ring: Int) {
        val uid = myUid ?: return
        FirebaseFirestore.getInstance().collection("alerts").document(t.id)
            .collection("responses").document("${uid}_ack")
            .set(hashMapOf<String, Any>(
                "type" to "ack", "ring" to ring, "at" to FieldValue.serverTimestamp()
            ))
            .addOnFailureListener { Log.d(TAG, "ack not written: ${it.message}") }
    }

    /** Fire the alarm on this phone once the alert's current ring reaches it. */
    private fun evaluate() {
        val svc = service ?: return
        val now = System.currentTimeMillis()
        val it = tracked.entries.iterator()
        while (it.hasNext()) {
            val t = it.next().value
            val age = maxOf(0L, now - t.createdMs)
            if (age > LIFETIME_MS) { t.reg?.remove(); it.remove(); continue }
            if (t.fired) continue
            val me = svc.lastKnownLocation() ?: continue
            val r = FloatArray(1)
            android.location.Location.distanceBetween(me.latitude, me.longitude, t.lat, t.lon, r)
            val ring = when {
                r[0] <= RING1_M -> 1
                r[0] <= RING2_M && ring2Open(t, age) -> 2
                else -> 0
            }
            if (ring == 0) continue
            t.fired = true
            sendAck(t, ring)
            svc.onResponderSos(ResponderAlert(t.name, t.lat, t.lon, r[0].toInt(), t.key, t.seq))
        }
    }
}
