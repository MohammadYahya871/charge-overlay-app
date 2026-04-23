package com.example.charge_overlay_app

import io.flutter.app.FlutterApplication

class ChargeOverlayApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        OverlayEngineHost.prewarm(this)
    }
}
