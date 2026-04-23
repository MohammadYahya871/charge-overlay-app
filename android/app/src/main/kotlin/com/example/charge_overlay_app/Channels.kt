package com.example.charge_overlay_app

import android.app.Activity
import android.app.Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.os.PowerManager
import android.provider.Settings
import android.service.notification.StatusBarNotification
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

object Channels {
    const val METHOD_CHANNEL = "charge_overlay_app/methods"
    const val EVENT_CHANNEL = "charge_overlay_app/charging_state"
    const val NOTIFICATION_EVENT_CHANNEL = "charge_overlay_app/notification_events"
}

object ChargingEventHub : EventChannel.StreamHandler {
    private var appContext: Context? = null
    private var eventSink: EventChannel.EventSink? = null
    private var batteryReceiver: BroadcastReceiver? = null

    fun initialize(context: Context) {
        appContext = context.applicationContext
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        publish(ChargingStateStore.snapshot().toMap())
        startBatteryUpdates()
    }

    override fun onCancel(arguments: Any?) {
        stopBatteryUpdates()
        eventSink = null
    }

    fun publish(state: Map<String, Any>) {
        eventSink?.success(state)
    }

    private fun startBatteryUpdates() {
        val context = appContext ?: return
        if (batteryReceiver != null) {
            return
        }

        batteryReceiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action != Intent.ACTION_BATTERY_CHANGED) {
                        return
                    }

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
                            source = when (plugged) {
                                BatteryManager.BATTERY_PLUGGED_AC -> "ac"
                                BatteryManager.BATTERY_PLUGGED_USB -> "usb"
                                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
                                BatteryManager.BATTERY_PLUGGED_DOCK -> "dock"
                                else -> "unknown"
                            },
                        ),
                    )
                }
            }

        val stickyIntent = context.registerReceiver(
            batteryReceiver,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        if (stickyIntent != null) {
            batteryReceiver?.onReceive(context, stickyIntent)
        }
    }

    private fun stopBatteryUpdates() {
        val context = appContext ?: return
        val receiver = batteryReceiver ?: return
        context.unregisterReceiver(receiver)
        batteryReceiver = null
    }
}

object NotificationEventHub : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun publish(payload: Map<String, Any>) {
        eventSink?.success(payload)
    }
}

fun configureFlutterChannels(
    context: Context,
    engine: FlutterEngine,
    activityProvider: (() -> Activity?)? = null,
) {
    ChargingEventHub.initialize(context)
    EventChannel(engine.dartExecutor.binaryMessenger, Channels.EVENT_CHANNEL)
        .setStreamHandler(ChargingEventHub)
    EventChannel(engine.dartExecutor.binaryMessenger, Channels.NOTIFICATION_EVENT_CHANNEL)
        .setStreamHandler(NotificationEventHub)

    MethodChannel(engine.dartExecutor.binaryMessenger, Channels.METHOD_CHANNEL)
        .setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchMode" -> {
                    val activity = activityProvider?.invoke()
                    result.success(
                        if (activity is ChargingOverlayActivity) "overlay" else "main",
                    )
                }

                "getSettings" -> result.success(SettingsRepository.read(context))
                "saveSettings" -> {
                    val arguments = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    SettingsRepository.write(context, arguments)
                    result.success(null)
                }

                "getChargingState" -> result.success(ChargingStateStore.snapshot().toMap())
                "syncMonitoringState" -> {
                    ChargingServiceController.sync(context)
                    result.success(null)
                }

                "isServiceRunning" -> result.success(ChargingServiceController.isServiceRunning())
                "canDrawOverlays" -> result.success(Settings.canDrawOverlays(context))
                "canReadNotifications" ->
                    result.success(NotificationAccessHelper.isNotificationAccessGranted(context))
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = context.getSystemService(PowerManager::class.java)
                    result.success(powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false)
                }
                "openOverlayPermissionSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${context.packageName}"),
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(null)
                }
                "openBatteryOptimizationSettings" -> {
                    val intent =
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    context.startActivity(intent)
                    result.success(null)
                }
                "openNotificationListenerSettings" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(null)
                }

                "showOverlayPreview" -> {
                    OverlayLauncher.showOverlay(context, preview = true)
                    result.success(null)
                }

                "dismissOverlay" -> {
                    ChargingMonitorService.activeService?.onOverlayDismissed()
                    ChargingOverlayActivity.activeInstance?.finish()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
}

object ChargingServiceController {
    @Volatile
    private var running = false

    fun setRunning(value: Boolean) {
        running = value
    }

    fun isServiceRunning(): Boolean = running

    fun sync(context: Context) {
        val settings = SettingsRepository.read(context)
        val enabled = settings["enabled"] as? Boolean ?: false
        if (enabled) {
            val serviceIntent = Intent(context, ChargingMonitorService::class.java)
            ContextCompat.startForegroundService(context, serviceIntent)
        } else {
            context.stopService(Intent(context, ChargingMonitorService::class.java))
        }
    }
}

object OverlayLauncher {
    fun showOverlay(context: Context, preview: Boolean = false) {
        val intent = Intent(context, ChargingOverlayActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
            putExtra("preview", preview)
        }
        context.startActivity(intent)
    }
}

object NotificationAccessHelper {
    fun isNotificationAccessGranted(context: Context): Boolean {
        val enabledListeners =
            Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
        return enabledListeners.contains(context.packageName)
    }

    fun toPayload(context: Context, sbn: StatusBarNotification): Map<String, Any>? {
        if (sbn.packageName == context.packageName) {
            return null
        }

        val notification = sbn.notification
        if ((notification.flags and Notification.FLAG_ONGOING_EVENT) != 0) {
            return null
        }

        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val bigText =
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val message = if (bigText.isNotBlank()) bigText else text
        if (title.isBlank() && message.isBlank()) {
            return null
        }

        val appName =
            runCatching {
                val appInfo = context.packageManager.getApplicationInfo(sbn.packageName, 0)
                context.packageManager.getApplicationLabel(appInfo).toString()
            }.getOrDefault(sbn.packageName)

        val payload = mutableMapOf<String, Any>(
            "appName" to appName,
            "title" to title,
            "message" to message,
            "packageName" to sbn.packageName,
        )

        extractIconBytes(context, sbn)?.let { payload["iconBytes"] = it }

        return payload
    }

    private fun extractIconBytes(context: Context, sbn: StatusBarNotification): ByteArray? {
        val notification = sbn.notification
        val extras = notification.extras

        (extras.getParcelable(Notification.EXTRA_LARGE_ICON_BIG) as? Bitmap)?.let {
            bitmapToPngBytes(it)?.let { bytes -> return bytes }
        }
        (extras.getParcelable(Notification.EXTRA_LARGE_ICON) as? Bitmap)?.let {
            bitmapToPngBytes(it)?.let { bytes -> return bytes }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            notification.getLargeIcon()?.loadDrawable(context)?.let { drawable ->
                drawableToPngBytes(drawable)?.let { return it }
            }
        }

        return runCatching {
            val appInfo = context.packageManager.getApplicationInfo(sbn.packageName, 0)
            val drawable = context.packageManager.getApplicationIcon(appInfo)
            drawableToPngBytes(drawable)
        }.getOrNull()
    }

    private fun bitmapToPngBytes(bitmap: Bitmap): ByteArray? {
        if (bitmap.width <= 0 || bitmap.height <= 0) {
            return null
        }
        return runCatching {
            ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                output.toByteArray()
            }
        }.getOrNull()
    }

    private fun drawableToPngBytes(drawable: Drawable): ByteArray? {
        if (drawable is BitmapDrawable) {
            drawable.bitmap?.let { return bitmapToPngBytes(it) }
        }

        val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: 128
        val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: 128
        return runCatching {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bitmapToPngBytes(bitmap)
        }.getOrNull()
    }
}
