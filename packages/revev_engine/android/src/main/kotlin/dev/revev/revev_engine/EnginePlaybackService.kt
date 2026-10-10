package dev.revev.revev_engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Keeps an explicitly started engine alive through screen lock. Never auto-restarts. */
class EnginePlaybackService : Service() {
    companion object {
        private const val CHANNEL = "engine_playback"
        private const val NOTIFICATION = 2711
        private const val STOP = "dev.revev.revev_engine.STOP"
        private var generation = 0L
        @Volatile var active = false; private set

        fun start(context: Context, location: Boolean) {
            val token = ++generation
            context.startForegroundService(Intent(context, EnginePlaybackService::class.java)
                .putExtra("generation", token).putExtra("location", location))
        }

        fun stop(context: Context) {
            ++generation
            context.stopService(Intent(context, EnginePlaybackService::class.java))
        }
    }

    private var ownedGeneration = -1L
    private var wakeLock: PowerManager.WakeLock? = null
    private var session: MediaSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Engine playback", NotificationManager.IMPORTANCE_LOW))
        session = MediaSession(this, "RevEV engine").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onStop() { stopEngine() }
                override fun onPause() { stopEngine() }
            })
            setPlaybackState(PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_STOP or PlaybackState.ACTION_PAUSE)
                .setState(PlaybackState.STATE_PLAYING, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1f).build())
            isActive = true
        }
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "RevEV:engine-playback")
            .apply { setReferenceCounted(false) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val token = intent?.getLongExtra("generation", -1L) ?: -1L
        if (token != generation) return START_NOT_STICKY
        ownedGeneration = token
        if (intent?.action == STOP || !EngineBridge.currentState.playing) {
            stopEngine()
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val stopIntent = Intent(this, EnginePlaybackService::class.java)
                .setAction(STOP).putExtra("generation", token)
            val stop = PendingIntent.getService(this, 0, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val launch = packageManager.getLaunchIntentForPackage(packageName)?.let {
                PendingIntent.getActivity(this, 0, it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }
            val notification = Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("RevEV engine running")
                .setContentText(if (intent?.getBooleanExtra("location", false) == true)
                    "GPS Drive continues with the screen off" else "Engine audio continues with the screen off")
                .setContentIntent(launch)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .addAction(Notification.Action.Builder(android.R.drawable.ic_media_pause, "Stop", stop).build())
                .setStyle(Notification.MediaStyle().setMediaSession(session!!.sessionToken)
                    .setShowActionsInCompactView(0))
                .build()
            if (Build.VERSION.SDK_INT >= 29) {
                val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                    if (intent?.getBooleanExtra("location", false) == true)
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
                startForeground(NOTIFICATION, notification, type)
            } else startForeground(NOTIFICATION, notification)
            wakeLock?.acquire()
            active = true
        } catch (e: Exception) {
            android.util.Log.e("RevEV", "Could not keep engine playback foreground", e)
            stopEngine()
            EngineBridge.updateState { it.copy(failed = true) }
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun stopEngine() {
        if (ownedGeneration == generation) EngineBridge.requestStop()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopEngine()
        stopSelf()
    }

    override fun onDestroy() {
        // An old service must not stop a newer playback request.
        stopEngine()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        session?.release()
        session = null
        active = false
        super.onDestroy()
    }
}
