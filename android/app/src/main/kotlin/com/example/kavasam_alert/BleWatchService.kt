package com.example.kavasam_alert

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.bluetooth.le.BluetoothLeScanner
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.telephony.SmsManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Foreground service that keeps listening for the SOS trigger device
 * (ESP32 BLE advertisement, company id 0xFFFE, packet type 0x01) even when
 * the app is closed or the screen is off.
 *
 * When an SOS packet arrives it:
 *  1. starts a looping alarm (alarm volume, max),
 *  2. sends an SMS (location + map link) to the victim's emergency numbers
 *     that are carried inside the packet,
 *  3. shows a full-screen high-priority alert (MainActivity -> SosAlertScreen).
 */
/** "Someone nearby needs help" as delivered by the cloud push. */
data class ResponderAlert(
    val name: String, val lat: Double, val lon: Double,
    val distM: Int, val key: String, val seq: Int
)

class BleWatchService : Service() {

    companion object {
        const val ACTION_SOS = "com.example.kavasam_alert.SOS"
        private const val CH_WATCH = "kavasam_watch"
        private const val CH_ALERT = "kavasam_sos_alert"
        private const val ID_WATCH = 4101
        const val ID_ALERT = 4102
        private const val COMPANY_ID = 0xFFFE
        private const val MAX_HOPS = 3            // BLE relay: phone -> phone -> phone
        private const val RELAY_SECONDS = 90L

        @Volatile var queuedResponder: ResponderAlert? = null

        @Volatile var instance: BleWatchService? = null
        @Volatile var pendingSos: HashMap<String, Any?>? = null

        fun start(ctx: Context) {
            ContextCompat.startForegroundService(ctx, Intent(ctx, BleWatchService::class.java))
        }

        fun stopAlarm() {
            instance?.stopAlarmInternal()
        }
    }

    private var scanner: BluetoothLeScanner? = null
    private var player: MediaPlayer? = null
    private val lastSeen = HashMap<String, Pair<Int, Long>>()
    private val handler = Handler(Looper.getMainLooper())
    private val names = HashMap<String, Pair<Int, String>>()      // address -> (seq, victim name)
    private val waiting = HashMap<String, Pair<Int, Runnable>>()  // address -> (seq, fire)
    private var voiceText: String? = null
    private var locListener: LocationListener? = null
    private var lastPush = 0L

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val n = NotificationCompat.Builder(this, CH_WATCH)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Kavasam Alert is active")
                .setContentText("Listening for nearby SOS devices")
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
            if (Build.VERSION.SDK_INT >= 29) {
                // connectedDevice (BLE) + location (so the phone keeps reporting its
                // position to the cloud while the app is closed). Android 14+ can refuse the
                // location type when started from boot -> fall back to BLE only.
                val both = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                try {
                    startForeground(ID_WATCH, n, both)
                } catch (e: Exception) {
                    startForeground(ID_WATCH, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
                }
            } else {
                startForeground(ID_WATCH, n)
            }
            startScan()
            setupResponder()
            queuedResponder?.let { q -> queuedResponder = null; onResponderSos(q) }
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopScan()
        stopAllRelays()
        ResponderNet.stopListening()
        stopLocationUpdates()
        stopAlarmInternal()
        instance = null
        super.onDestroy()
    }

    // ---------------------------------------------------------------- scan

    @SuppressLint("MissingPermission")
    private fun startScan() {
        if (scanner != null) return
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter ?: return
        if (!adapter.isEnabled) return
        val sc = adapter.bluetoothLeScanner ?: return

        // Hardware filter: company id 0xFFFE + packet type 0x01 (SOS). A
        // filter is required for scanning to continue while the screen is off.
        // type 0x01 = SOS data, type 0x02 = victim-name packet.
        val sosFilter = ScanFilter.Builder()
            .setManufacturerData(COMPANY_ID, byteArrayOf(0x01), byteArrayOf(0xFF.toByte()))
            .build()
        val nameFilter = ScanFilter.Builder()
            .setManufacturerData(COMPANY_ID, byteArrayOf(0x02), byteArrayOf(0xFF.toByte()))
            .build()
        val relayFilter = ScanFilter.Builder()
            .setManufacturerData(COMPANY_ID, byteArrayOf(0x03), byteArrayOf(0xFF.toByte()))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
            .build()
        sc.startScan(listOf(sosFilter, nameFilter, relayFilter), settings, callback)
        scanner = sc
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        try { scanner?.stopScan(callback) } catch (_: Exception) {}
        scanner = null
    }

    private val callback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) = handle(result)
        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach { handle(it) }
        }
    }

    private fun readInt(b: ByteArray, o: Int): Int =
        (b[o].toInt() and 0xFF) or
            ((b[o + 1].toInt() and 0xFF) shl 8) or
            ((b[o + 2].toInt() and 0xFF) shl 16) or
            ((b[o + 3].toInt() and 0xFF) shl 24)

    private fun decodePhone(d: ByteArray, off: Int): String? {
        val sb = StringBuilder()
        for (i in 0 until 5) {
            val b = d[off + i].toInt() and 0xFF
            val hi = b shr 4
            val lo = b and 0x0F
            if (hi > 9) break
            sb.append(hi)
            if (lo > 9) break
            sb.append(lo)
        }
        return if (sb.length >= 6) sb.toString() else null
    }

    /**
     * data = manufacturer payload WITHOUT the 2-byte company id.
     *  SOS  packet: [0]=1 [1] flags [2] seq [3..6] lat [7..10] lon [11..] 5-byte BCD numbers
     *  Name packet: [0]=2 [1] seq [2..] victim name (UTF-8)
     */
    private fun handle(r: ScanResult) {
        val data = r.scanRecord?.getManufacturerSpecificData(COMPANY_ID) ?: return
        if (data.size < 2) return
        val addr = r.device.address
        when (data[0].toInt()) {
            2 -> {
                val seq = data[1].toInt() and 0xFF
                val name = String(data, 2, data.size - 2, Charsets.UTF_8)
                    .trim { it == '\u0000' || it.isWhitespace() }
                names[addr] = Pair(seq, name)
                val w = waiting[addr]
                if (w != null && w.first == seq) {   // an SOS was waiting for this name
                    handler.removeCallbacks(w.second)
                    w.second.run()
                }
            }
            1 -> handleSos(addr, data)
            3 -> handleRelay(data)
        }
    }

    private fun handleSos(addr: String, data: ByteArray) {
        if (data.size < 11) return
        val flags = data[1].toInt() and 0xFF
        val seq = data[2].toInt() and 0xFF
        val gpsOk = (flags and 1) != 0
        val lat = readInt(data, 3) / 1_000_000.0
        val lon = readInt(data, 7) / 1_000_000.0

        val phones = ArrayList<String>()
        var off = 11
        while (off + 5 <= data.size && phones.size < 3) {
            decodePhone(data, off)?.let { phones.add(it) }
            off += 5
        }

        // flags bit2 = the fix is the device's last known one (not live);
        // byte 21 = how old it is, in units of 10 s.
        val stale = (flags and 4) != 0
        val ageSec = if (stale) (if (data.size > 21) (data[21].toInt() and 0xFF) * 10 else 600) else -1

        // The device repeats the same SOS for ~60 s: alert only once per
        // button press (new sequence number) or after a long silence.
        val now = System.currentTimeMillis()
        val prev = lastSeen[addr]
        lastSeen[addr] = Pair(seq, now)
        if (prev != null && prev.first == seq && now - prev.second < 120_000) {
            // Same button press: send a follow-up SMS if the live GPS position
            // appeared or the victim moved.
            maybeFollowUp(addr, seq, gpsOk && ageSec < 0, lat, lon)
            return
        }

        val known = names[addr]
        if (known != null && known.first == seq) {
            onSos(known.second, gpsOk, lat, lon, phones, addr, seq, ageSec)
            return
        }
        // Name packet not heard yet: wait briefly for it, then alert anyway.
        val fire = Runnable {
            waiting.remove(addr)
            val nm = names[addr]?.takeIf { it.first == seq }?.second ?: ""
            onSos(nm, gpsOk, lat, lon, phones, addr, seq, ageSec)
        }
        waiting[addr] = Pair(seq, fire)
        handler.postDelayed(fire, 5000)
    }

    // ------------------------------------------------ follow-up location SMS

    private class Track(
        val seq: Int, var lat: Double, var lon: Double, var live: Boolean,
        var lastSms: Long, var count: Int, val phones: List<String>, val name: String
    )
    private val tracks = HashMap<String, Track>()

    private fun dialNumber(p: String) = if (p.length == 10) "+91$p" else p

    /**
     * While the device keeps broadcasting the same SOS, text the contacts again
     * when the first live GPS fix arrives, or the victim has moved > 100 m
     * (at most one SMS per minute, 5 follow-ups per SOS).
     * Uses the tag KAVASAM-UPDATE so the contact's phone does not re-alarm.
     */
    private fun maybeFollowUp(addr: String, seq: Int, live: Boolean, lat: Double, lon: Double) {
        val t = tracks[addr] ?: return
        if (t.seq != seq || !live || t.count >= 5) return
        val now = System.currentTimeMillis()
        if (now - t.lastSms < 60_000) return
        if (t.live) {
            val d = FloatArray(1)
            Location.distanceBetween(t.lat, t.lon, lat, lon, d)
            if (d[0] < 100f) return
        }
        val la = String.format(Locale.US, "%.6f", lat)
        val lo = String.format(Locale.US, "%.6f", lon)
        val who = if (t.name.isEmpty()) "Someone" else t.name
        val msg = "KAVASAM-UPDATE|$who\nLocation update for $who (live GPS):\n" +
            "$la, $lo\nMap: https://maps.google.com/?q=$la,$lo"
        for (p in t.phones) sendSms(dialNumber(p), msg)
        t.lat = lat; t.lon = lon; t.live = true; t.lastSms = now; t.count++
    }

    // ----------------------------------------------------------------- SOS

    private fun onSos(name: String, gpsOk: Boolean, lat: Double, lon: Double, phones: List<String>, deviceKey: String, seq: Int, ageSec: Int) {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kavasam:sos")
        wl.acquire(20_000)
        try {
            var useLat = lat
            var useLon = lon
            var hasLoc = gpsOk
            var approx = false
            if (!gpsOk) {
                // Victim's GPS has no fix yet -> this phone is within BLE
                // range of the victim, so its own position is a good estimate.
                lastKnownLocation()?.let {
                    useLat = it.latitude; useLon = it.longitude; hasLoc = true; approx = true
                }
            }

            startAlarm()
            startVoice(if (name.isEmpty()) "Someone nearby is in danger. Please help." else "$name is in danger. Please help.")

            val origin = origin16(deviceKey)
            val alertId = if (hasLoc) ResponderNet.makeAlertId(originKey(origin), seq) else null
            val message = buildMessage(name, hasLoc, approx, useLat, useLon, ageSec, alertId)
            val sent = ArrayList<String>()
            val failed = ArrayList<String>()
            for (p in phones) {
                val dial = dialNumber(p)
                if (sendSms(dial, message)) sent.add(dial) else failed.add(dial)
            }
            tracks[deviceKey] = Track(
                seq, useLat, useLon, gpsOk && ageSec < 0,
                System.currentTimeMillis(), 0, ArrayList(phones), name
            )

            pendingSos = hashMapOf<String, Any?>(
                "name" to name,
                "lat" to useLat,
                "lon" to useLon,
                "hasLocation" to hasLoc,
                "numbers" to ArrayList(sent + failed),
                "sent" to sent,
                "failed" to failed
            )
            showAlertAndLaunch(name)

            if (hasLoc) {
                seenBefore(origin, seq)
                // 1) BLE mesh: re-broadcast so phones out of the device's range still hear it.
                relayAdvertise(origin, seq, 1, name, useLat, useLon)
                // 2) Cloud: alert the nearest app users, no BLE needed for them.
                ResponderNet.raiseAlertAsync(
                    this, originKey(origin), seq, name, useLat, useLon,
                    alertId ?: ResponderNet.makeAlertId(originKey(origin), seq)
                )
            }
        } finally {
            if (wl.isHeld) wl.release()
        }
    }

    private fun buildMessage(name: String, hasLoc: Boolean, approx: Boolean, lat: Double, lon: Double, ageSec: Int, alertId: String? = null): String {
        val loc = if (hasLoc) {
            val la = String.format(Locale.US, "%.6f", lat)
            val lo = String.format(Locale.US, "%.6f", lon)
            (if (approx) "Approx. location (sender's phone is near the victim): "
             else if (ageSec >= 0) "Last known GPS location (about ${maxOf(1, ageSec / 60)} min old): "
             else "Live GPS location: ") +
                "$la, $lo\nMap: https://maps.google.com/?q=$la,$lo"
        } else {
            "Location: not available yet."
        }
        val who = if (name.isEmpty()) "Someone" else name
        return "KAVASAM-SOS|$who\nSOS ALERT\n$who is in danger and needs help. " +
            "You are listed as their emergency contact.\n$loc\n" +
            "Please call them / contact Police (100) immediately.\n" +
            (if (alertId != null) "Ref:$alertId\n" else "") +
            "(Sent automatically by Kavasam Alert)"
    }

    @Suppress("DEPRECATION")
    private fun sendSms(to: String, msg: String): Boolean {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED) return false
        return try {
            val sm: SmsManager = SimSms.manager(this) ?: return false
            sm.sendMultipartTextMessage(to, null, sm.divideMessage(msg), null, null)
            true
        } catch (e: Exception) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    fun lastKnownLocation(): Location? {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) return null
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        ).mapNotNull {
            try { lm.getLastKnownLocation(it) } catch (e: Exception) { null }
        }.maxByOrNull { it.time }
    }

    // ------------------------------------------- SOS received by SMS

    private var lastSmsAlert = 0L

    /** Emergency contact's phone: tagged SMS arrived -> same alarm + full-screen alert. */
    fun onSmsSos(name: String, hasLoc: Boolean, lat: Double, lon: Double, ref: String = "") {
        val now = System.currentTimeMillis()
        if (now - lastSmsAlert < 120_000) return   // several nearby phones may send the same SMS
        lastSmsAlert = now
        startAlarm()
        startVoice(if (name.isEmpty()) "Someone you know is in danger. Please help." else "$name is in danger. Please help.")
        pendingSos = hashMapOf<String, Any?>(
            "name" to name, "lat" to lat, "lon" to lon, "hasLocation" to hasLoc,
            "numbers" to ArrayList<String>(), "sent" to ArrayList<String>(),
            "failed" to ArrayList<String>(), "fromSms" to true, "ref" to ref
        )
        showAlertAndLaunch(name)
    }

    // ------------------------------------------- responder network

    /** Push alert from the cloud: this phone is among the nearest app users. */
    fun onResponderSos(a: ResponderAlert) {
        val origin = a.key.toIntOrNull(16) ?: origin16(a.key)
        if (seenBefore(origin, a.seq)) return       // already alerted (BLE or earlier push)
        onNearbySos(a.name, a.lat, a.lon, a.distM, origin, a.seq, 0, "cloud")
    }

    /** BLE relay packet (type 0x03) from another phone: [1]=hop [2..3]=origin [4]=seq [5..8]=lat [9..12]=lon [13..]=name */
    private fun handleRelay(d: ByteArray) {
        if (d.size < 13) return
        val hop = d[1].toInt() and 0xFF
        val origin = (d[2].toInt() and 0xFF) or ((d[3].toInt() and 0xFF) shl 8)
        val seq = d[4].toInt() and 0xFF
        if (seenBefore(origin, seq)) return
        val lat = readInt(d, 5) / 1_000_000.0
        val lon = readInt(d, 9) / 1_000_000.0
        val name = if (d.size > 13) String(d, 13, d.size - 13, Charsets.UTF_8)
            .trim { it == '\u0000' || it.isWhitespace() } else ""
        onNearbySos(name, lat, lon, -1, origin, seq, hop, "relay")
    }

    /** Common path for a nearby (non-victim) phone: alarm + screen + keep the chain going. */
    private fun onNearbySos(name: String, lat: Double, lon: Double, distIn: Int,
                            origin: Int, seq: Int, hop: Int, via: String) {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kavasam:nearby")
        wl.acquire(20_000)
        try {
            var distM = distIn
            if (distM < 0) {
                lastKnownLocation()?.let {
                    val r = FloatArray(1)
                    Location.distanceBetween(it.latitude, it.longitude, lat, lon, r)
                    distM = r[0].toInt()
                }
            }
            val who = if (name.isEmpty()) "Someone" else name
            if (player == null) {
                startAlarm()
                startVoice(if (distM >= 0) "$who needs help, about $distM metres from you."
                           else "$who needs help nearby.")
            }
            pendingSos = hashMapOf<String, Any?>(
                "name" to name, "lat" to lat, "lon" to lon, "hasLocation" to true,
                "numbers" to ArrayList<String>(), "sent" to ArrayList<String>(),
                "failed" to ArrayList<String>(), "fromResponder" to true, "distance" to distM
            )
            showAlertAndLaunch(name)
            // keep the mesh going: BLE re-broadcast, and tell the cloud if we are online
            if (hop < MAX_HOPS) relayAdvertise(origin, seq, hop + 1, name, lat, lon)
            if (via == "relay") ResponderNet.raiseAlertAsync(this, originKey(origin), seq, name, lat, lon)
        } finally {
            if (wl.isHeld) wl.release()
        }
    }

    // ------------------------------------------------------- BLE relay (mesh)

    private val relaySeen = HashMap<String, Long>()
    private val relayAds = HashMap<String, AdvertiseCallback>()

    private fun origin16(s: String) = s.hashCode() and 0xFFFF
    private fun originKey(o: Int) = String.format(Locale.US, "%04x", o)

    /** true if this SOS was already handled in the last 5 min; otherwise marks it handled. */
    private fun seenBefore(origin: Int, seq: Int): Boolean {
        val now = System.currentTimeMillis()
        relaySeen.entries.removeAll { now - it.value > 300_000 }
        val k = "$origin-$seq"
        if (relaySeen.containsKey(k)) return true
        relaySeen[k] = now
        return false
    }

    private fun truncateUtf8(s: String, maxBytes: Int): ByteArray {
        val sb = StringBuilder()
        var used = 0
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            val chars = Character.toChars(cp)
            val bytes = String(chars).toByteArray(Charsets.UTF_8).size
            if (used + bytes > maxBytes) break
            sb.append(chars); used += bytes; i += chars.size
        }
        return sb.toString().toByteArray(Charsets.UTF_8)
    }

    private fun writeInt(b: ByteArray, o: Int, v: Int) {
        b[o] = (v and 0xFF).toByte(); b[o + 1] = ((v shr 8) and 0xFF).toByte()
        b[o + 2] = ((v shr 16) and 0xFF).toByte(); b[o + 3] = ((v shr 24) and 0xFF).toByte()
    }

    @SuppressLint("MissingPermission")
    private fun relayAdvertise(origin: Int, seq: Int, hop: Int, name: String, lat: Double, lon: Double) {
        try {
            if (Build.VERSION.SDK_INT >= 31 &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE)
                != PackageManager.PERMISSION_GRANTED) return
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter ?: return
            if (!adapter.isEnabled) return
            val adv = adapter.bluetoothLeAdvertiser ?: return
            val key = "$origin-$seq"
            if (relayAds.containsKey(key)) return

            val nb = truncateUtf8(name, 12)
            val buf = ByteArray(13 + nb.size)
            buf[0] = 0x03; buf[1] = hop.toByte()
            buf[2] = (origin and 0xFF).toByte(); buf[3] = ((origin shr 8) and 0xFF).toByte()
            buf[4] = seq.toByte()
            writeInt(buf, 5, (lat * 1_000_000).roundToInt())
            writeInt(buf, 9, (lon * 1_000_000).roundToInt())
            System.arraycopy(nb, 0, buf, 13, nb.size)

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(false).setTimeout(0).build()
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false).setIncludeTxPowerLevel(false)
                .addManufacturerData(COMPANY_ID, buf).build()
            val cb = object : AdvertiseCallback() {
                override fun onStartFailure(errorCode: Int) { relayAds.remove(key) }
            }
            relayAds[key] = cb
            adv.startAdvertising(settings, data, cb)
            handler.postDelayed({ stopRelay(key) }, RELAY_SECONDS * 1000)
        } catch (_: Exception) {
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopRelay(key: String) {
        val cb = relayAds.remove(key) ?: return
        try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            adapter?.bluetoothLeAdvertiser?.stopAdvertising(cb)
        } catch (_: Exception) {}
    }

    private fun stopAllRelays() { relayAds.keys.toList().forEach { stopRelay(it) } }

    /** Opt-in: keep the cloud updated with this phone's approximate position. */
    private fun setupResponder() {
        if (!ResponderNet.enabled(this)) {
            stopLocationUpdates()
            ResponderNet.stopListening()
            return
        }
        startLocationUpdates()                 // keeps the phone's last-known position fresh
        ResponderNet.startListening(this)      // Firestore listener for nearby alerts
    }

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {
        if (locListener != null) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) return
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val l = object : LocationListener {
            override fun onLocationChanged(loc: Location) {
                val now = System.currentTimeMillis()
                if (now - lastPush < 60_000) return
                lastPush = now
                // position stays on the phone: distance to an alert is computed locally
            }
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        try {
            for (p in listOf(LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)) {
                if (lm.isProviderEnabled(p)) lm.requestLocationUpdates(p, 300_000L, 150f, l)
            }
            locListener = l
            lastKnownLocation()?.let { l.onLocationChanged(it) }
        } catch (_: Exception) {
        }
    }

    private fun stopLocationUpdates() {
        val l = locListener ?: return
        try {
            (getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(l)
        } catch (_: Exception) {
        }
        locListener = null
    }

    // --------------------------------------------------------------- alarm

    private fun startAlarm() {
        if (player != null) return
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val mp = MediaPlayer.create(this, R.raw.sos_alarm, attrs, am.generateAudioSessionId()) ?: return
            mp.isLooping = true
            mp.start()
            player = mp
        } catch (e: Exception) {
            player = null
        }
    }

    /** Speaks the victim's name every 10 s while the alarm is active. */
    private val voiceTick = object : Runnable {
        override fun run() {
            val t = voiceText ?: return
            if (player == null) return
            VoiceAlert.speak(this@BleWatchService, t,
                { player?.setVolume(0.25f, 0.25f) },
                { player?.setVolume(1f, 1f) })
            handler.postDelayed(this, 10_000)
        }
    }

    private fun startVoice(text: String) {
        voiceText = text
        handler.removeCallbacks(voiceTick)
        handler.post(voiceTick)
    }

    fun stopAlarmInternal() {
        handler.removeCallbacks(voiceTick)
        voiceText = null
        VoiceAlert.stop()
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(ID_ALERT)
    }

    // ------------------------------------------------- full-screen alert

    private fun showAlertAndLaunch(name: String) {
        val launch = Intent(this, MainActivity::class.java).apply {
            action = ACTION_SOS
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pi = PendingIntent.getActivity(
            this, 1, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(this, CH_ALERT)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(if (name.isEmpty()) "\uD83D\uDEA8 SOS ALERT — someone nearby needs help!" else "\uD83D\uDEA8 $name is in danger!")
            .setContentText("Tap to open the emergency screen")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(0xFFD32F2F.toInt())
            .setFullScreenIntent(pi, true)
            .setContentIntent(pi)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(ID_ALERT, n)

        // Direct launch (allowed while "Display over other apps" is granted).
        try { startActivity(launch) } catch (_: Exception) {}
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CH_WATCH, "SOS watcher", NotificationManager.IMPORTANCE_LOW)
        )
        val alert = NotificationChannel(CH_ALERT, "SOS alerts", NotificationManager.IMPORTANCE_HIGH).apply {
            setSound(null, null) // alarm is played by the service itself
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(alert)
    }
}