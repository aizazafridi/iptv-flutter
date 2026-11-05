package com.iptv.iptv_flutter

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaCodecList
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multiViewChannel: MethodChannel? = null
    private var focusRequest: AudioFocusRequest? = null
    private var ownsFocus = false
    private val audioManager by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        runOnUiThread { multiViewChannel?.invokeMethod("audioFocus", change == AudioManager.AUDIOFOCUS_GAIN) }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        multiViewChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamora/multiview")
        multiViewChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> Thread {
                    val decoders = mutableListOf<Map<String, Any>>()
                    try {
                        for (codec in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
                            if (codec.isEncoder) continue
                            if (Build.VERSION.SDK_INT >= 29 && !codec.isHardwareAccelerated) continue
                            for (mime in codec.supportedTypes) {
                                if (mime != "video/avc" && mime != "video/hevc") continue
                                try {
                                    val instances = if (Build.VERSION.SDK_INT >= 23)
                                        codec.getCapabilitiesForType(mime).maxSupportedInstances else 1
                                    decoders.add(mapOf("codec" to codec.name, "mime" to mime, "instances" to instances))
                                } catch (_: Exception) { }
                            }
                        }
                    } catch (_: Exception) { }
                    runOnUiThread { result.success(mapOf("decoders" to decoders)) }
                }.start()
                "requestAudioFocus" -> result.success(requestMultiViewFocus())
                "abandonAudioFocus" -> { abandonMultiViewFocus(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    @Suppress("DEPRECATION")
    private fun requestMultiViewFocus(): Boolean {
        val granted = if (Build.VERSION.SDK_INT >= 26) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                .setOnAudioFocusChangeListener(focusListener).build().also { focusRequest = it }
            audioManager.requestAudioFocus(request)
        } else audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        ownsFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return ownsFocus
    }
    @Suppress("DEPRECATION")
    private fun abandonMultiViewFocus() {
        if (!ownsFocus) return
        if (Build.VERSION.SDK_INT >= 26) focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        else audioManager.abandonAudioFocus(focusListener)
        ownsFocus = false
    }
    override fun onDestroy() {
        abandonMultiViewFocus()
        multiViewChannel?.setMethodCallHandler(null)
        multiViewChannel = null
        super.onDestroy()
    }
}
