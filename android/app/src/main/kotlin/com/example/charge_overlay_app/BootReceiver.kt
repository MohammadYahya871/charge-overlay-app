package com.example.charge_overlay_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (
            intent?.action == Intent.ACTION_BOOT_COMPLETED ||
                intent?.action == Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            ChargingServiceController.sync(context)
        }
    }
}
