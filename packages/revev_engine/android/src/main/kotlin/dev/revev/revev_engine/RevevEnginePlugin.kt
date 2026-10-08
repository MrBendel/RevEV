package dev.revev.revev_engine

import android.app.Activity
import android.content.Intent
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
import android.os.SystemClock
import java.io.File
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class RevevEnginePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, SensorEventListener, LocationListener, EngineBridge.CommandHandler, PluginRegistry.RequestPermissionsResultListener, PluginRegistry.ActivityResultListener {
    companion object {
        private const val LOCATION_PERMISSION_REQUEST_CODE = 1001
    }

    private var exportResult: MethodChannel.Result? = null
    private var exportFile: File? = null
    private fun logDirectory() = File(context.filesDir, "session-logs").also { it.mkdirs() }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 1002) return false
        val result = exportResult ?: return true
        val source = exportFile
        exportResult = null
        exportFile = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || source == null) {
            result.success(null)
            return true
        }
        Thread {
            try {
                context.contentResolver.openOutputStream(uri)?.use { output ->
                    source.inputStream().use { it.copyTo(output) }
                } ?: error("Could not open destination")
                android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(null) }
            } catch (e: Exception) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.error("export_failed", e.message, null)
                }
            }
        }.start()
        return true
    }

    private lateinit var channel: MethodChannel
    private lateinit var audioManager: AudioManager
    private var playing = false
    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var focusRequest: AudioFocusRequest? = null
    private val focusPolicy = AudioFocusPolicy({ nativeFocusGain(it) }, { stop() })

    private var locationManager: LocationManager? = null
    private var sensorManager: SensorManager? = null
    private var accelSensor: Sensor? = null
    private var gravitySensor: Sensor? = null
    private var sensorsActive = false

    private var currentSpeedMps = 0.0f
    private var currentAccelMps2 = 0.0f
    private var currentLateralAccelMps2 = 0.0f
    private var currentTireSquealSensitivity = 0.5f
    private var currentAggressiveness = 0.5f
    private var currentDriveMode = 0
    private var mountingPositionName = "auto"

    // Gravity isolation filter for raw accelerometer
    private val gravity = FloatArray(3)
    private var gravityInitialized = false
    private var lastSensorTimestampNs = 0L

    // Low-pass smoothing filter on forward and lateral acceleration to prevent road vibration jitter
    private var smoothedAccel = 0.0f
    private var smoothedLateral = 0.0f

    // Dead-reckoning velocity integration for instant responsiveness before/between GPS fixes
    private val motion = DriveMotionEstimator()
    private val motionHandler by lazy { android.os.Handler(android.os.Looper.getMainLooper()) }
    private val motionTick = object : Runnable {
        override fun run() {
            if (!sensorsActive || !playing || currentDriveMode != 1) return
            motion.step(nowSeconds())
            publishMotion()
            motionHandler.postDelayed(this, 20)
        }
    }
    private val replayMotion = DriveMotionEstimator()
    private var replayActive = false
    private var replayTime = 0.0
    private var effectiveMount = "unknown"
    private var locationError: String? = null
    private var gpsAccuracyM: Float? = null
    private val linearAcceleration = FloatArray(3)
    private fun nowSeconds() = SystemClock.elapsedRealtimeNanos() * 1e-9
    private fun resetMotion() {
        motion.reset()
        lastLocation = null
        gpsAccuracyM = null
        locationError = null
        effectiveMount = "unknown"
        linearAcceleration.fill(0.0f)
        currentSpeedMps = 0.0f
        currentAccelMps2 = 0.0f
        currentLateralAccelMps2 = 0.0f
    }

    private fun publishMotion() {
        currentSpeedMps = motion.speedMps.toFloat()
        currentAccelMps2 = motion.acceleration(nowSeconds()).toFloat()
        nativeDriveTelemetry(currentSpeedMps, currentAccelMps2, currentAggressiveness,
            currentDriveMode, currentLateralAccelMps2, currentTireSquealSensitivity)
        EngineBridge.updateState { it.copy(vehicleSpeedMps = currentSpeedMps.toDouble(), accelMps2 = currentAccelMps2.toDouble()) }
    }
    private var lastLocation: Location? = null

    private external fun nativeStart(root: String, preset: String): Int
    private external fun nativeStop()
    private external fun nativeShutdown()
    private external fun nativeControls(throttle: Float, volume: Float)
    private external fun nativeFocusGain(gain: Float)
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
        gravitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GRAVITY)
        channel = MethodChannel(binding.binaryMessenger, "revev_engine")
        channel.setMethodCallHandler(this)
        EngineBridge.commandHandler = this
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
        if (playing && currentDriveMode == 1 && sensorsActive) {
            requestLocationUpdatesIfPermitted()
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
        if (playing && currentDriveMode == 1 && sensorsActive) {
            requestLocationUpdatesIfPermitted()
        }
    }

    override fun onDetachedFromActivity() {
        exportResult?.error("export_interrupted", "Activity detached", null)
        exportResult = null
        exportFile = null
        if (playing) {
            stop()
        }
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val granted = hasLocationPermission()
            if (granted) {
                if (playing && currentDriveMode == 1) {
                    if (sensorsActive) startLocationUpdates() else startSensors()
                }
            }
            channel.invokeMethod("onLocationPermissionResult", mapOf("granted" to granted))
            return true
        }
        return false
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

    private fun resetSensorFilters() {
        gravityInitialized = false
        lastSensorTimestampNs = 0L
        smoothedAccel = 0.0f
        smoothedLateral = 0.0f
    }

    private fun startSensors() {
        if (sensorsActive) return
        sensorsActive = true
        resetSensorFilters()
        resetMotion()
        motionHandler.post(motionTick)

        accelSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        gravitySensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }

        requestLocationUpdatesIfPermitted()
    }

    private fun hasLocationPermission(): Boolean {
        val hasFine = context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        return hasFine || hasCoarse
    }

    private fun requestLocationUpdatesIfPermitted() {
        if (hasLocationPermission()) {
            startLocationUpdates()
        } else {
            activity?.let { act ->
                act.requestPermissions(
                    arrayOf(
                        android.Manifest.permission.ACCESS_FINE_LOCATION,
                        android.Manifest.permission.ACCESS_COARSE_LOCATION
                    ),
                    LOCATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    private fun startLocationUpdates() {
        if (!hasLocationPermission()) return
        val mgr = locationManager ?: return
        try {
            val providers = mgr.allProviders ?: listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            for (provider in providers) {
                if (provider == LocationManager.PASSIVE_PROVIDER) {
                    try {
                        mgr.requestLocationUpdates(provider, 100L, 0.0f, this, android.os.Looper.getMainLooper())
                    } catch (e: Exception) { locationError = e.message ?: "Location subscription failed" }
                    continue
                }
                if (mgr.isProviderEnabled(provider)) {
                    val minTime = if (provider == LocationManager.GPS_PROVIDER) 100L else 250L
                    try {
                        mgr.requestLocationUpdates(provider, minTime, 0.0f, this, android.os.Looper.getMainLooper())
                    } catch (e: Exception) { locationError = e.message ?: "Location subscription failed" }
                }
            }

            for (provider in providers) {
                try {
                    val loc = mgr.getLastKnownLocation(provider)
                    if (loc != null) {
                        val ageMs = (SystemClock.elapsedRealtimeNanos() - loc.elapsedRealtimeNanos) / 1000000L
                        if (ageMs in 0L..2500L) {
                            onLocationChanged(loc)
                            break
                        }
                    }
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }

    private fun stopSensors() {
        motionHandler.removeCallbacks(motionTick)
        if (!sensorsActive) return
        sensorsActive = false
        sensorManager?.unregisterListener(this)
        try {
            locationManager?.removeUpdates(this)
        } catch (_: Exception) {}
        resetSensorFilters()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || currentDriveMode != 1 || !playing) return

        if (event.sensor.type == Sensor.TYPE_GRAVITY) {
            gravity[0] = event.values[0]
            gravity[1] = event.values[1]
            gravity[2] = event.values[2]
            gravityInitialized = true
            return
        }

        val dt = if (lastSensorTimestampNs > 0L) {
            val delta = (event.timestamp - lastSensorTimestampNs) * 1e-9f
            if (delta in 0.001f..1.0f) delta else 0.02f
        } else {
            0.02f
        }
        lastSensorTimestampNs = event.timestamp

        val rawX = event.values[0]
        val rawY = event.values[1]
        val rawZ = event.values[2]

        val linearX: Float
        val linearY: Float
        val linearZ: Float

        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            if (!gravityInitialized) {
                gravity[0] = rawX
                gravity[1] = rawY
                gravity[2] = rawZ
                gravityInitialized = true
            } else {
                // Time constant ~ 3.0s isolates steady gravity / mount tilt while passing vehicle acceleration
                val timeConstant = 3.0f
                val alpha = timeConstant / (timeConstant + dt)
                gravity[0] = alpha * gravity[0] + (1.0f - alpha) * rawX
                gravity[1] = alpha * gravity[1] + (1.0f - alpha) * rawY
                gravity[2] = alpha * gravity[2] + (1.0f - alpha) * rawZ
            }
            linearX = rawX - gravity[0]
            linearY = rawY - gravity[1]
            linearZ = rawZ - gravity[2]
        } else {
            // TYPE_LINEAR_ACCELERATION: gravity is already subtracted by Android sensor HAL
            linearX = rawX
            linearY = rawY
            linearZ = rawZ
        }
        linearAcceleration[0] = linearX
        linearAcceleration[1] = linearY
        linearAcceleration[2] = linearZ

        // Project out vertical gravity component (road bumps, potholes) to isolate horizontal vehicle motion
        val gravNormSq = gravity[0] * gravity[0] + gravity[1] * gravity[1] + gravity[2] * gravity[2]
        val (horizX, horizY, horizZ) = if (gravNormSq > 25.0f) {
            val gravNorm = kotlin.math.sqrt(gravNormSq)
            val gx = gravity[0] / gravNorm
            val gy = gravity[1] / gravNorm
            val gz = gravity[2] / gravNorm
            val vertDot = linearX * gx + linearY * gy + linearZ * gz
            Triple(linearX - vertDot * gx, linearY - vertDot * gy, linearZ - vertDot * gz)
        } else {
            Triple(linearX, linearY, linearZ)
        }

        val effectiveMounting = if (mountingPositionName == "auto") {
            val absGx = kotlin.math.abs(gravity[0])
            val absGy = kotlin.math.abs(gravity[1])
            val absGz = kotlin.math.abs(gravity[2])
            when {
                absGy >= absGz && absGy >= absGx -> "uprightPortrait"
                absGx >= absGz && absGx > absGy -> "uprightLandscapeLeft"
                else -> "trayTopForward"
            }
        } else {
            mountingPositionName
        }

        effectiveMount = effectiveMounting

        // Transform device axes to vehicle forward & lateral acceleration based on mounting position
        val rawForward = when (effectiveMounting) {
            "trayTopForward" -> horizY
            "trayTopRearward" -> -horizY
            "trayTopLeft" -> -horizX
            "trayTopRight" -> horizX
            "uprightPortrait", "uprightLandscapeLeft", "uprightLandscapeRight" -> -horizZ
            else -> horizY
        }

        val rawLateral = when (effectiveMounting) {
            "trayTopForward", "trayTopRearward", "uprightPortrait" -> kotlin.math.abs(horizX)
            "trayTopLeft", "trayTopRight", "uprightLandscapeLeft", "uprightLandscapeRight" -> kotlin.math.abs(horizY)
            else -> kotlin.math.abs(horizX)
        }

        // Deadzone micro-vibrations (< 0.08 m/s^2)
        val deadbandForward = if (kotlin.math.abs(rawForward) < 0.08f) 0.0f else rawForward
        val deadbandLateral = if (rawLateral < 0.08f) 0.0f else rawLateral

        // Low-pass smoothing on forward and lateral acceleration to prevent chassis vibration jitter
        val smoothAlpha = dt / (0.12f + dt)
        smoothedAccel += (deadbandForward - smoothedAccel) * smoothAlpha
        smoothedLateral += (deadbandLateral - smoothedLateral) * smoothAlpha

        currentAccelMps2 = smoothedAccel
        currentLateralAccelMps2 = smoothedLateral

        // Integrate on every IMU sample, including between fresh GPS fixes.
        motion.step(nowSeconds(), currentAccelMps2.toDouble())
        publishMotion()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onLocationChanged(location: Location) {
        if (currentDriveMode != 1 || !playing || !sensorsActive) return
        val now = nowSeconds()
        val fixTime = location.elapsedRealtimeNanos * 1e-9
        // Position-only network fixes are not reliable speed observations. Do not
        // derive a large speed from a GPS/network position jump.
        val speed = if (location.hasSpeed()) location.speed.toDouble() else Double.NaN
        val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else Double.NaN
        motion.step(now)
        val speedAccuracy = if (android.os.Build.VERSION.SDK_INT >= 26 && location.hasSpeedAccuracy())
            location.speedAccuracyMetersPerSecond.toDouble() else null
        if (motion.gps(now, fixTime, speed, accuracy, speedAccuracy)) {
            lastLocation = location
            gpsAccuracyM = location.accuracy
            locationError = null
        }
        publishMotion()
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    private fun stop() {
        stopSensors()
        nativeStop()
        focusPolicy.end()
        playing = false
        replayActive = false
        EngineBridge.updateState { it.copy(playing = false, stopping = false, rpm = 0.0, gear = 0, vehicleSpeedMps = 0.0, accelMps2 = 0.0, boostBar = 0.0) }
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sessionLogDirectory" -> result.success(logDirectory().absolutePath)
            "exportSessionLog" -> {
                val name = call.argument<String>("name") ?: ""
                val directory = logDirectory().canonicalFile
                val source = File(directory, name).canonicalFile
                val act = activity
                if (source.parentFile != directory || !name.endsWith(".jsonl") || !source.isFile) {
                    result.error("invalid_log", "Session log not found", null)
                } else if (act == null || exportResult != null) {
                    result.error("export_busy", "File picker unavailable", null)
                } else {
                    exportFile = source
                    exportResult = result
                    try {
                        act.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, name)
                        }, 1002)
                    } catch (e: Exception) {
                        exportFile = null
                        exportResult = null
                        result.error("export_failed", e.message, null)
                    }
                }
            }
            "start" -> {
                stop()
                val focusToken = focusPolicy.begin()
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setOnAudioFocusChangeListener { change ->
                        focusPolicy.changed(change, focusToken)
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
                        if (currentDriveMode == 1) {
                            startSensors()
                        }
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
                val newDriveMode = (call.argument<Number>("driveMode") ?: currentDriveMode).toInt()
                val prevDriveMode = currentDriveMode
                currentDriveMode = newDriveMode
                if (newDriveMode != 2) replayActive = false

                currentAggressiveness = (call.argument<Number>("aggressiveness") ?: currentAggressiveness).toFloat()
                call.argument<Number>("tireSquealSensitivity")?.let { currentTireSquealSensitivity = it.toFloat() }

                call.argument<String>("mountingPosition")?.let { newPos ->
                    if (mountingPositionName != newPos) {
                        mountingPositionName = newPos
                        resetSensorFilters()
                    }
                }

                // In GPS Drive (mode 1), speed and acceleration come from native sensors (GPS + accelerometer).
                // Do NOT let Flutter overwrite them with 0.0.
                if (currentDriveMode != 1) {
                    currentSpeedMps = (call.argument<Number>("speedMps") ?: currentSpeedMps).toFloat()
                    currentAccelMps2 = (call.argument<Number>("accelMps2") ?: currentAccelMps2).toFloat()
                    call.argument<Number>("lateralAccelMps2")?.let { currentLateralAccelMps2 = it.toFloat() }
                } else if (prevDriveMode != 1) {
                    // Transitioned into GPS Drive mode: clear old sim speed/accel
                    currentSpeedMps = 0.0f
                    currentAccelMps2 = 0.0f
                    currentLateralAccelMps2 = 0.0f
                    resetSensorFilters()
                }

                if (playing && currentDriveMode == 1) {
                    if (!sensorsActive) startSensors()
                } else if (sensorsActive) {
                    stopSensors()
                }

                val sample = call.argument<Map<String, Any?>>("testSample")
                if (sample != null && currentDriveMode == 2 && playing) {
                    val time = (sample["timeSeconds"] as? Number)?.toDouble() ?: 0.0
                    if (sample["reset"] == true) replayMotion.reset()
                    replayActive = true
                    replayTime = time
                    replayMotion.step(time, (sample["accelMps2"] as? Number)?.toDouble())
                    (sample["gpsSpeedMps"] as? Number)?.let {
                        val fixTime = (sample["gpsTimeSeconds"] as? Number)?.toDouble() ?: time
                        replayMotion.gps(time, fixTime, it.toDouble(), 5.0)
                    }
                    currentSpeedMps = replayMotion.speedMps.toFloat()
                    currentAccelMps2 = replayMotion.acceleration(time).toFloat()
                } else if (currentDriveMode == 2) {
                    replayActive = false
                }
                nativeDriveTelemetry(
                    currentSpeedMps,
                    currentAccelMps2,
                    currentAggressiveness,
                    if (replayActive) 1 else currentDriveMode,
                    currentLateralAccelMps2,
                    currentTireSquealSensitivity
                )
                EngineBridge.updateState { it.copy(driveMode = currentDriveMode, shiftAggressiveness = currentAggressiveness) }
                result.success(null)
            }
            "stats" -> {
                if (playing && currentDriveMode == 1) {
                    motion.step(nowSeconds())
                    publishMotion()
                }
                val s = nativeStats()
                if (s[3] != 0.0 || s[4] != 0.0) stop()
                val rpm = s[0]
                val boost = if (s.size > 6) s[6] else 0.0
                val gear = if (s.size > 7) s[7].toInt() else 0
                val vehicleSpeed = if (s.size > 8) s[8] else 0.0
                val tireSquealLevel = if (s.size > 9) s[9] else 0.0
                val accelMps2 = if (s.size > 10) s[10] else currentAccelMps2.toDouble()
                EngineBridge.updateState {
                    it.copy(
                        rpm = rpm,
                        gear = gear,
                        vehicleSpeedMps = vehicleSpeed,
                        accelMps2 = accelMps2,
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
                    "accelMps2" to accelMps2,
                    "tireSquealLevel" to tireSquealLevel,
                    "motion" to ((if (replayActive) replayMotion.diagnostics(replayTime)
                        else motion.diagnostics(nowSeconds())) + mapOf(
                        "supported" to true,
                        "targetRpm" to if (s.size > 11) s[11] else null,
                        "engineThrottle" to if (s.size > 12) s[12] else null,
                        "audioFocusGain" to if (s.size > 13) s[13] else null,
                        "replay" to replayActive,
                        "sensorsActive" to sensorsActive,
                        "accelerometerAvailable" to (accelSensor != null),
                        "sensorType" to accelSensor?.stringType,
                        "gravityReady" to gravityInitialized,
                        "linearX" to linearAcceleration[0],
                        "linearY" to linearAcceleration[1],
                        "linearZ" to linearAcceleration[2],
                        "locationPermission" to hasLocationPermission(),
                        "gpsEnabled" to (locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true),
                        "gpsAccuracyM" to gpsAccuracyM,
                        "provider" to lastLocation?.provider,
                        "mount" to effectiveMount,
                        "locationError" to locationError
                    ))
                ))
            }
            "hasLocationPermission" -> {
                result.success(hasLocationPermission())
            }
            "requestLocationPermission" -> {
                if (hasLocationPermission()) {
                    if (playing && currentDriveMode == 1 && !sensorsActive) {
                        startSensors()
                    }
                    result.success(true)
                } else {
                    activity?.let { act ->
                        act.requestPermissions(
                            arrayOf(
                                android.Manifest.permission.ACCESS_FINE_LOCATION,
                                android.Manifest.permission.ACCESS_COARSE_LOCATION
                            ),
                            LOCATION_PERMISSION_REQUEST_CODE
                        )
                        result.success(false)
                    } ?: result.error("no_activity", "Activity not attached", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (EngineBridge.commandHandler == this) {
            EngineBridge.commandHandler = null
        }
        stop()
        channel.setMethodCallHandler(null)
        activity = null
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
        currentDriveMode = mode
        if (playing) {
            if (currentDriveMode == 1) {
                if (!sensorsActive) startSensors()
            } else {
                if (sensorsActive) stopSensors()
            }
        }
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
