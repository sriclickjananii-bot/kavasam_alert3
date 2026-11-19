package com.example.kavasam_alert

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener

/** Speaks "<name> is in danger" on the alarm stream (text-to-speech). */
object VoiceAlert {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var pendingText: String? = null
    private var onStartCb: (() -> Unit)? = null
    private var onDoneCb: (() -> Unit)? = null

    fun speak(ctx: Context, text: String, onStart: (() -> Unit)? = null, onDone: (() -> Unit)? = null) {
        onStartCb = onStart
        onDoneCb = onDone
        val engine = tts
        if (engine != null && ready) {
            say(engine, text)
            return
        }
        pendingText = text
        if (engine == null) {
            tts = TextToSpeech(ctx.applicationContext) { status ->
                val e = tts
                if (e != null && status == TextToSpeech.SUCCESS) {
                    e.setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    e.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) { onStartCb?.invoke() }
                        override fun onDone(utteranceId: String?) { onDoneCb?.invoke() }
                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) { onDoneCb?.invoke() }
                    })
                    ready = true
                    pendingText?.let { say(e, it); pendingText = null }
                } else {
                    onDoneCb?.invoke()
                }
            }
        }
    }

    private fun say(e: TextToSpeech, text: String) {
        val params = Bundle().apply {
            putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_ALARM)
        }
        e.speak("$text $text", TextToSpeech.QUEUE_FLUSH, params, "kavasam_voice")
    }

    fun stop() {
        try { tts?.stop() } catch (_: Exception) {}
    }
}