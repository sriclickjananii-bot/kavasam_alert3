package com.example.kavasam_alert

import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.telephony.SmsManager
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SMS_CHANNEL = "com.example.kavasam_alert/sms"
    private val WATCH_CHANNEL = "com.example.kavasam_alert/watch"
    private val FILES_CHANNEL = "com.example.kavasam_alert/files"
    private var watchChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        showOverLockScreen(intent)
        if (intent.action == BleWatchService.ACTION_SOS) pushPendingSos()
    }

    /** SOS launches turn the screen on and show over the lock screen. */
    private fun showOverLockScreen(i: Intent?) {
        if (i?.action != BleWatchService.ACTION_SOS) return
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }


    /** Shares this app's own installed APK (as Kavasam_Alert.apk) through the Android share sheet. */
    private fun shareApk(text: String, title: String): Boolean {
        return try {
            val src = java.io.File(applicationInfo.sourceDir)
            val dir = java.io.File(cacheDir, "share")
            dir.mkdirs()
            val dst = java.io.File(dir, "Kavasam_Alert.apk")
            src.copyTo(dst, overwrite = true)
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this, "$packageName.fileprovider", dst
            )
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "application/vnd.android.package-archive"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TEXT, text)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(send, title))
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Copies a recorded video into the phone gallery (Movies/KavasamAlert). */
    private fun saveVideoToGallery(path: String): Boolean {
        return try {
            val src = java.io.File(path)
            if (!src.exists()) return false
            val name = "KavasamSOS_" + System.currentTimeMillis() + ".mp4"
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, name)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                if (Build.VERSION.SDK_INT >= 29) {
                    put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/KavasamAlert")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
            }
            val collection = if (Build.VERSION.SDK_INT >= 29)
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            val uri = contentResolver.insert(collection, values) ?: return false
            contentResolver.openOutputStream(uri)?.use { out ->
                src.inputStream().use { it.copyTo(out) }
            } ?: return false
            if (Build.VERSION.SDK_INT >= 29) {
                values.clear()
                values.put(MediaStore.Video.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun pushPendingSos() {
        val m = BleWatchService.pendingSos ?: return
        val ch = watchChannel ?: return
        BleWatchService.pendingSos = null
        ch.invokeMethod("onSos", m)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "sendSms") {
                    val to = call.argument<String>("to")
                    val message = call.argument<String>("message")
                    if (to == null || message == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val smsManager: SmsManager = SimSms.manager(this)
                            ?: throw IllegalStateException("no SmsManager")
                        val parts = smsManager.divideMessage(message)
                        smsManager.sendMultipartTextMessage(to, null, parts, null, null)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }


        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareApk" -> result.success(
                        shareApk(call.argument<String>("text") ?: "", call.argument<String>("title") ?: "Share")
                    )
                    "getSims" -> result.success(SimSms.list(this))
                    "saveVideo" -> {
                        val path = call.argument<String>("path")
                        result.success(if (path == null) false else saveVideoToGallery(path))
                    }
                    else -> result.notImplemented()
                }
            }

        watchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startWatch" -> {
                        try { BleWatchService.start(this); result.success(true) }
                        catch (e: Exception) { result.success(false) }
                    }
                    "stopAlarm" -> {
                        BleWatchService.stopAlarm()
                        (getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager)
                            .cancel(BleWatchService.ID_ALERT)
                        result.success(true)
                    }
                    "getPendingSos" -> {
                        val m = BleWatchService.pendingSos
                        BleWatchService.pendingSos = null
                        result.success(m)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}