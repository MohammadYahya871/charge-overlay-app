package com.example.charge_overlay_app

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import androidx.core.app.NotificationCompat
import kotlin.math.abs
import kotlin.math.sqrt

class ChargingMonitorService : Service(), SensorEventListener {
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private lateinit var keyguardManager: KeyguardManager
    private lateinit var powerManager: PowerManager

    private var isScreenLocked = false
    private var isMotionStable = false
    private var dismissedUntilReset = false
    private var sensorRegistered = false
    private var lastMotionAt = 0L
    private var lastOverlayLaunchAt = 0L

    private val forceOverlayRunnable = Runnable { maybeShowOverlay(force = true) }
    private val stableOverlayRunnable = Runnable { maybeShowOverlay(force = false) }

    private val stateReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_POWER_CONNECTED -> {
                        dismissedUntilReset = false
                        updateFromBatteryIntent()
                        refreshScreenLockState()
                        lastMotionAt = SystemClock.elapsedRealtime()
                        isMotionStable = false
                        evaluateMotionTracking()
                        scheduleForceOverlayLaunch()
                    }

                    Intent.ACTION_POWER_DISCONNECTED -> {
                        resetOverlaySuppression()
                        mainHandler.removeCallbacks(forceOverlayRunnable)
                        mainHandler.removeCallbacks(stableOverlayRunnable)
                        updateFromBatteryIntent()
                        unregisterMotionTracking()
                        ChargingOverlayActivity.activeInstance?.finish()
                    }

                    Intent.ACTION_SCREEN_OFF -> {
                        refreshScreenLockState()
                        lastMotionAt = SystemClock.elapsedRealtime()
                        isMotionStable = false
                        evaluateMotionTracking()
                    }

                    Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> {
                        refreshScreenLockState()
                        if (!isScreenLocked) {
                            resetOverlaySuppression()
                        }
                        evaluateMotionTracking()
                    }
                }
            }
        }

    override fun onCreate() {
        super.onCreate()
        activeService = this
        sensorManager = getSystemService(SensorManager::class.java)
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        keyguardManager = getSystemService(KeyguardManager::class.java)
        powerManager = getSystemService(PowerManager::class.java)
        ChargingServiceController.setRunning(true)
        createNotificationChannel()
        startAsForeground()
        registerReceivers()
        updateFromBatteryIntent()
        refreshScreenLockState()
        evaluateMotionTracking()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(forceOverlayRunnable)
        mainHandler.removeCallbacks(stableOverlayRunnable)
        unregisterMotionTracking()
        unregisterReceiver(stateReceiver)
        activeService = null
        ChargingServiceController.setRunning(false)
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val settings = SettingsRepository.read(this)
        val enabled = settings["enabled"] as? Boolean ?: false
        if (!enabled) {
            stopSelf()
            return START_NOT_STICKY
        }

        updateFromBatteryIntent()
        refreshScreenLockState()
        evaluateMotionTracking()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onSensorChanged(event: SensorEvent?) {
        val reading = event ?: return
        val now = SystemClock.elapsedRealtime()
        val magnitude = sqrt(
            (reading.values[0] * reading.values[0]) +
                (reading.values[1] * reading.values[1]) +
                (reading.values[2] * reading.values[2]),
        )
        val delta = abs(magnitude - SensorManager.GRAVITY_EARTH)

        if (delta > MOTION_THRESHOLD) {
            lastMotionAt = now
            if (isMotionStable) {
                isMotionStable = false
            }
            resetOverlaySuppression()
            mainHandler.removeCallbacks(stableOverlayRunnable)
            return
        }

        if (!dismissedUntilReset && !isMotionStable && now - lastMotionAt >= STABLE_WINDOW_MS) {
            isMotionStable = true
            scheduleStableOverlayLaunch()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    fun onOverlayDismissed() {
        dismissedUntilReset = true
        isMotionStable = false
        lastMotionAt = SystemClock.elapsedRealtime()
        mainHandler.removeCallbacks(stableOverlayRunnable)
        evaluateMotionTracking()
    }

    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun registerReceivers() {
        val filter =
            IntentFilter().apply {
                addAction(Intent.ACTION_POWER_CONNECTED)
                addAction(Intent.ACTION_POWER_DISCONNECTED)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_USER_PRESENT)
            }
        registerReceiver(stateReceiver, filter)
    }

    private fun refreshScreenLockState() {
        isScreenLocked = keyguardManager.isKeyguardLocked || !powerManager.isInteractive
    }

    private fun evaluateMotionTracking() {
        val snapshot = ChargingStateStore.snapshot()
        val shouldTrack =
            snapshot.isPlugged &&
                snapshot.isCharging &&
                isScreenLocked &&
                ChargingOverlayActivity.activeInstance == null

        if (shouldTrack) {
            registerMotionTracking()
        } else {
            unregisterMotionTracking()
            isMotionStable = false
        }

        if (shouldTrack && !dismissedUntilReset && isMotionStable) {
            scheduleStableOverlayLaunch()
        } else {
            mainHandler.removeCallbacks(stableOverlayRunnable)
        }
    }

    private fun registerMotionTracking() {
        if (sensorRegistered || accelerometer == null) {
            return
        }
        lastMotionAt = SystemClock.elapsedRealtime()
        sensorRegistered =
            sensorManager.registerListener(
                this,
                accelerometer,
                SensorManager.SENSOR_DELAY_NORMAL,
            )
    }

    private fun unregisterMotionTracking() {
        if (!sensorRegistered) {
            return
        }
        sensorManager.unregisterListener(this)
        sensorRegistered = false
    }

    private fun maybeShowOverlay(force: Boolean) {
        if (!Settings.canDrawOverlays(this)) {
            return
        }
        if (ChargingOverlayActivity.activeInstance != null) {
            return
        }

        val settings = SettingsRepository.read(this)
        val enabled = settings["enabled"] as? Boolean ?: false
        if (!enabled) {
            return
        }

        updateFromBatteryIntent()
        val snapshot = ChargingStateStore.snapshot()
        if (!snapshot.isPlugged || !snapshot.isCharging) {
            return
        }
        if (!force) {
            if (!isScreenLocked || !isMotionStable || dismissedUntilReset) {
                return
            }
        }

        val now = SystemClock.elapsedRealtime()
        if (now - lastOverlayLaunchAt < OVERLAY_LAUNCH_DEBOUNCE_MS) {
            return
        }
        lastOverlayLaunchAt = now
        OverlayLauncher.showOverlay(this)
    }

    private fun scheduleForceOverlayLaunch() {
        mainHandler.removeCallbacks(forceOverlayRunnable)
        mainHandler.postDelayed(forceOverlayRunnable, CHARGER_SETTLE_DELAY_MS)
    }

    private fun scheduleStableOverlayLaunch() {
        mainHandler.removeCallbacks(stableOverlayRunnable)
        mainHandler.postDelayed(stableOverlayRunnable, STABLE_TRIGGER_DELAY_MS)
    }

    private fun resetOverlaySuppression() {
        dismissedUntilReset = false
    }

    private fun updateFromBatteryIntent() {
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (intent != null) {
            updateFromIntent(intent)
        }
    }

    private fun updateFromIntent(intent: Intent) {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, 0)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100).coerceAtLeast(1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)

        val percent = ((level * 100f) / scale).toInt().coerceIn(0, 100)
        ChargingStateStore.update(
            ChargingSnapshot(
                level = percent,
                isCharging =
                    status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL,
                isPlugged = plugged != 0,
                source = pluggedSource(plugged),
            ),
        )
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Charge Overlay")
            .setContentText("Listening for charger events")
            .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
            .setOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Charge Overlay Monitor",
                NotificationManager.IMPORTANCE_LOW,
            )
        manager.createNotificationChannel(channel)
    }

    private fun pluggedSource(plugged: Int): String {
        return when (plugged) {
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            BatteryManager.BATTERY_PLUGGED_DOCK -> "dock"
            else -> "unknown"
        }
    }

    companion object {
        @Volatile
        var activeService: ChargingMonitorService? = null

        private const val CHANNEL_ID = "charge_overlay_monitor"
        private const val NOTIFICATION_ID = 404
        private const val CHARGER_SETTLE_DELAY_MS = 220L
        private const val STABLE_TRIGGER_DELAY_MS = 140L
        private const val OVERLAY_LAUNCH_DEBOUNCE_MS = 1500L
        private const val STABLE_WINDOW_MS = 3200L
        private const val MOTION_THRESHOLD = 0.55f
    }
}
