package com.example.charge_overlay_app

import java.util.concurrent.atomic.AtomicReference

data class ChargingSnapshot(
    val level: Int = 0,
    val isCharging: Boolean = false,
    val isPlugged: Boolean = false,
    val source: String = "unknown",
) {
    fun toMap(): Map<String, Any> = mapOf(
        "level" to level,
        "isCharging" to isCharging,
        "isPlugged" to isPlugged,
        "source" to source,
    )
}

object ChargingStateStore {
    private val current = AtomicReference(ChargingSnapshot())

    fun snapshot(): ChargingSnapshot = current.get()

    fun update(snapshot: ChargingSnapshot) {
        current.set(snapshot)
        ChargingEventHub.publish(snapshot.toMap())
    }
}
