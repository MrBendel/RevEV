package dev.revev.revev_engine

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Bundle
import java.io.File
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class RevevEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, SensorEventListener, LocationListener, EngineBridge.CommandHandler {
    private lateinit var channel: MethodChannel
    private lateinit var audioManager: AudioManager
    private var playing = false
    private lateinit var context: Context
    private var focusRequest: AudioFocusRequest? = null

    private var locationManager: LocationManager? = null
    private var sensorManager: SensorManager? = null
    private var accelSensor: Sensor? = null
    private var sensorsActive = false

    private var currentSpeedMps = 0.0f
    private var currentAccelMps2 = 0.0f
    private var currentLateralAccelMps2 = 0.0f
    private var currentTireSquealSensitivity = 0.5f
    private var currentAggressiveness = 0.5f
    private var currentDriveMode = 0
    private var mountingPositionName = "trayTopForward"

    private external fun nativeStart(root: String, preset: String): Int
    private external fun nativeStop()
    private external fun nativeShutdown()
    private external fun nativeControls(throttle: Float, volume: Float)
    private external fun nativeListeningMix(mode: Int, strength: Float)
    private external fun nativeDriveTelemetry(
        speedMps: Float,
        accelMps2: Float,
        aggressiveness: Float,
        driveMode: Int,
        lateralAccelMps2: Float,
        tireSquealSensitivity: Float
    )
    private external fun nativeStats(): DoubleArray

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        System.loadLibrary("revev_audio")
        context = binding.applicationContext
        audioManager = binding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        locationManager = binding.applicationContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        sensorManager = binding.applicationContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        accelSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        channel = MethodChannel(binding.binaryMessenger, "revev_engine")
        channel.setMethodCallHandler(this)
        EngineBridge.commandHandler = this
    }

    private fun prepareEngines(): String {
        // Version this directory when bundled definitions change. Never load user scripts.
        val root = File(context.filesDir, "engine-library-v4")
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

    private fun startSensors() {
        if (sensorsActive) return
        sensorsActive = true
        accelSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        try {
            if (context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                locationManager?.requestLocationUpdates(LocationManager.GPS_PROVIDER, 100L, 0.0f, this)
            }
        } catch (_: SecurityException) {
            // Graceful fallback if permission not granted
        }
    }

    private fun stopSensors() {
        if (!sensorsActive) return
        sensorsActive = false
        sensorManager?.unregisterListener(this)
        try {
            locationManager?.removeUpdates(this)
        } catch (_: SecurityException) {}
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || currentDriveMode != 1) return
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val forwardAccel = when (mountingPositionName) {
            "trayTopForward" -> y
            "trayTopRearward" -> -y
            "trayTopLeft" -> x
            "trayTopRight" -> -x
            "uprightPortrait", "uprightLandscapeLeft", "uprightLandscapeRight" -> -z
            else -> y
        }
        val lateralAccel = when (mountingPositionName) {
            "trayTopForward", "trayTopRearward", "uprightPortrait" -> kotlin.math.abs(x)
            "trayTopLeft", "trayTopRight", "uprightLandscapeLeft", "uprightLandscapeRight" -> kotlin.math.abs(y)
            else -> kotlin.math.abs(x)
        }
        currentAccelMps2 = forwardAccel
        currentLateralAccelMps2 = lateralAccel
        nativeDriveTelemetry(
            currentSpeedMps,
            currentAccelMps2,
            currentAggressiveness,
            currentDriveMode,
            currentLateralAccelMps2,
            currentTireSquealSensitivity
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onLocationChanged(location: Location) {
        if (currentDriveMode != 1) return
        if (location.hasSpeed()) {
            currentSpeedMps = location.speed
        }
        nativeDriveTelemetry(
            currentSpeedMps,
            currentAccelMps2,
            currentAggressiveness,
            currentDriveMode,
            currentLateralAccelMps2,
            currentTireSquealSensitivity
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    private fun stop() {
        stopSensors()
        nativeStop()
        playing = false
        EngineBridge.updateState { it.copy(playing = false, stopping = false, rpm = 0.0, gear = 0, vehicleSpeedMps = 0.0, boostBar = 0.0) }
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
                    if (playing) {
                        val chosenPreset = call.argument<String>("preset") ?: "porsche/911_carrera_32"
                        EngineBridge.updateState { it.copy(playing = true, stopping = false, failed = false, presetId = chosenPreset) }
                        result.success(null)
                    } else { stop(); result.error("audio_start", "Audio output could not start (code $code).", null) }
                }
            }
            "stop" -> { stop(); result.success(null) }
            "shutdown" -> { if (playing) nativeShutdown(); result.success(null) }
            "controls" -> {
                val throttle = (call.argument<Number>("throttle") ?: 0).toFloat()
                val volume = (call.argument<Number>("volume") ?: 0.15).toFloat()
                nativeControls(throttle, volume)
                EngineBridge.updateState { it.copy(throttle = throttle) }
                result.success(null)
            }
            "listeningMix" -> {
                nativeListeningMix((call.argument<Number>("mode") ?: 0).toInt(),
                    (call.argument<Number>("strength") ?: 0.5).toFloat())
                result.success(null)
            }
            "driveTelemetry" -> {
                currentSpeedMps = (call.argument<Number>("speedMps") ?: currentSpeedMps).toFloat()
                currentAccelMps2 = (call.argument<Number>("accelMps2") ?: currentAccelMps2).toFloat()
                currentAggressiveness = (call.argument<Number>("aggressiveness") ?: currentAggressiveness).toFloat()
                currentDriveMode = (call.argument<Number>("driveMode") ?: currentDriveMode).toInt()
                call.argument<Number>("lateralAccelMps2")?.let { currentLateralAccelMps2 = it.toFloat() }
                call.argument<Number>("tireSquealSensitivity")?.let { currentTireSquealSensitivity = it.toFloat() }
                call.argument<String>("mountingPosition")?.let { mountingPositionName = it }

                if (currentDriveMode == 1 && !sensorsActive) {
                    startSensors()
                } else if (currentDriveMode != 1 && sensorsActive) {
                    stopSensors()
                }

                nativeDriveTelemetry(
                    currentSpeedMps,
                    currentAccelMps2,
                    currentAggressiveness,
                    currentDriveMode,
                    currentLateralAccelMps2,
                    currentTireSquealSensitivity
                )
                EngineBridge.updateState { it.copy(driveMode = currentDriveMode, shiftAggressiveness = currentAggressiveness) }
                result.success(null)
            }
            "stats" -> {
                val s = nativeStats()
                if (s[3] != 0.0 || s[4] != 0.0) stop()
                val rpm = s[0]
                val boost = if (s.size > 6) s[6] else 0.0
                val gear = if (s.size > 7) s[7].toInt() else 0
                val vehicleSpeed = if (s.size > 8) s[8] else 0.0
                val tireSquealLevel = if (s.size > 9) s[9] else 0.0
                EngineBridge.updateState {
                    it.copy(
                        rpm = rpm,
                        gear = gear,
                        vehicleSpeedMps = vehicleSpeed,
                        boostBar = boost,
                        tireSquealLevel = tireSquealLevel,
                        playing = playing,
                        stopping = (playing && s[5] != 0.0),
                        failed = (s[3] != 0.0)
                    )
                }
                result.success(mapOf(
                    "rpm" to rpm,
                    "workMs" to s[1],
                    "underruns" to s[2],
                    "failed" to (s[3] != 0.0),
                    "playing" to playing,
                    "stopping" to (playing && s[5] != 0.0),
                    "boost" to boost,
                    "gear" to gear,
                    "vehicleSpeed" to vehicleSpeed,
                    "tireSquealLevel" to tireSquealLevel
                ))
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (EngineBridge.commandHandler == this) {
            EngineBridge.commandHandler = null
        }
        stop(); channel.setMethodCallHandler(null)
    }

    override fun onStartEngine(presetId: String?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            channel.invokeMethod("onRemoteStart", mapOf("preset" to (presetId ?: "porsche/911_carrera_32")))
        }
    }

    override fun onStopEngine() {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            channel.invokeMethod("onRemoteStop", null)
        }
    }

    override fun onSetPreset(presetId: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            channel.invokeMethod("onRemoteSetPreset", mapOf("preset" to presetId))
        }
    }

    override fun onSetDriveMode(mode: Int) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            channel.invokeMethod("onRemoteSetDriveMode", mapOf("driveMode" to mode))
        }
    }

    override fun onSetAggressiveness(aggressiveness: Float) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            channel.invokeMethod("onRemoteSetAggressiveness", mapOf("aggressiveness" to aggressiveness))
        }
    }
}
