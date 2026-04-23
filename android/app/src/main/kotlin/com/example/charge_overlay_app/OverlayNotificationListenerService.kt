package com.example.charge_overlay_app

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class OverlayNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (ChargingOverlayActivity.activeInstance == null) {
            return
        }

        val settings = SettingsRepository.read(this)
        val enabled = settings["enabled"] as? Boolean ?: false
        val showNotifications = settings["showNotifications"] as? Boolean ?: true
        if (!enabled || !showNotifications) {
            return
        }

        val payload = NotificationAccessHelper.toPayload(this, sbn) ?: return
        NotificationEventHub.publish(payload)
    }
}
