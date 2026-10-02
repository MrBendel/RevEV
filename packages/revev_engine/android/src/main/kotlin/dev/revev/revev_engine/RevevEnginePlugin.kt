package dev.revev.revev_engine

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import java.io.File
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class RevevEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var audioManager: AudioManager
    private var playing = false
    private lateinit var context: Context
    private var focusRequest: AudioFocusRequest? = null
    private external fun nativeStart(root: String, preset: String): Int
    private external fun nativeStop()
    private external fun nativeShutdown()
    private external fun nativeControls(throttle: Float, volume: Float)
    private external fun nativeListeningMix(mode: Int, strength: Float)
    private external fun nativeStats(): DoubleArray
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        System.loadLibrary("revev_audio")
        context = binding.applicationContext
        audioManager = binding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        channel = MethodChannel(binding.binaryMessenger, "revev_engine")
        channel.setMethodCallHandler(this)
    }
    private fun prepareEngines(): String {
        // Version this directory when bundled definitions change. Never load user scripts.
        val root = File(context.filesDir, "engine-library-v3")
        if (!File(root, ".ready").exists()) {
            fun copy(asset: String, target: File) {
                val children = context.assets.list(asset) ?: emptyArray()
                if (children.isEmpty()) {
                    target.parentFile?.mkdirs()
                    context.assets.open(asset).use { input -> target.outputStream().use { input.copyTo(it) } }
                } else {
                    target.mkdirs()
                    children.forEach { copy("$asset/$it", File(target, it)) }
                }
            }
            copy("engine-sim", root)
            File(root, ".ready").writeText("1")
        }
        return root.absolutePath
    }
    private fun stop() {
        nativeStop()
        playing = false
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = null
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                stop()
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setOnAudioFocusChangeListener { change ->
                        if (change != AudioManager.AUDIOFOCUS_GAIN) stop()
                    }.build()
                focusRequest = request
                if (audioManager.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    stop()
                    result.error("audio_focus", "Another app is using audio. Try again when it finishes.", null)
                } else {
                    val code = try { nativeStart(prepareEngines(), call.argument<String>("preset") ?: "porsche/911_carrera_32") }
                    catch (e: Exception) {
                        stop(); result.error("engine_assets", "Could not prepare bundled engines: ${e.message}", null)
                        return
                    }
                    playing = code == 0
                    if (playing) result.success(null)
                    else { stop(); result.error("audio_start", "Audio output could not start (code $code).", null) }
                }
            }
            "stop" -> { stop(); result.success(null) }
            "shutdown" -> { if (playing) nativeShutdown(); result.success(null) }
            "controls" -> {
                nativeControls((call.argument<Number>("throttle") ?: 0).toFloat(),
                    (call.argument<Number>("volume") ?: 0.15).toFloat())
                result.success(null)
            }
            "listeningMix" -> {
                nativeListeningMix((call.argument<Number>("mode") ?: 0).toInt(),
                    (call.argument<Number>("strength") ?: 0.5).toFloat())
                result.success(null)
            }
            "stats" -> {
                val s = nativeStats()
                if (s[3] != 0.0 || s[4] != 0.0) stop()
                result.success(mapOf("rpm" to s[0], "workMs" to s[1], "underruns" to s[2],
                    "failed" to (s[3] != 0.0), "playing" to playing, "stopping" to (playing && s[5] != 0.0),
                    "boost" to (if (s.size > 6) s[6] else 0.0)))
            }
            else -> result.notImplemented()
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop(); channel.setMethodCallHandler(null)
    }
}
