package com.example.charge_overlay_app

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

object OverlayEngineHost {
    private const val ENGINE_ID = "charge_overlay_engine"

    fun get(context: Context): FlutterEngine {
        return FlutterEngineCache.getInstance()[ENGINE_ID] ?: prewarm(context)
    }

    fun prewarm(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance()[ENGINE_ID]?.let { return it }

        val engine = FlutterEngine(context.applicationContext)
        GeneratedPluginRegistrant.registerWith(engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }
}
