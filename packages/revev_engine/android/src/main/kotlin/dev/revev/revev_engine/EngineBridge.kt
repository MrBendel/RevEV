package dev.revev.revev_engine

import java.util.concurrent.CopyOnWriteArrayList

object EngineBridge {
    data class State(
        val playing: Boolean = false,
        val stopping: Boolean = false,
        val failed: Boolean = false,
        val rpm: Double = 0.0,
        val gear: Int = 0,
        val vehicleSpeedMps: Double = 0.0,
        val boostBar: Double = 0.0,
        val presetId: String = "porsche/911_carrera_32",
        val driveMode: Int = 0, // 0 = manual, 1 = gps, 2 = sim
        val shiftAggressiveness: Float = 0.5f,
        val throttle: Float = 0.0f,
        val tireSquealLevel: Double = 0.0,
        val accelMps2: Double = 0.0
    ) {
        val speedKmh: Double get() = vehicleSpeedMps * 3.6
        val speedMph: Double get() = vehicleSpeedMps * 2.23694
        val accelG: Double get() = accelMps2 / 9.80665
        val gearDisplay: String get() = if (gear > 0) "D$gear" else "N"
    }

    interface Listener {
        fun onEngineStateChanged(state: State)
    }

    interface CommandHandler {
        fun onStartEngine(presetId: String?)
        fun onStopEngine()
        fun onSetPreset(presetId: String)
        fun onSetDriveMode(mode: Int)
        fun onSetAggressiveness(aggressiveness: Float)
    }

    @Volatile
    var currentState: State = State()
        private set

    private val listeners = CopyOnWriteArrayList<Listener>()

    @Volatile
    var commandHandler: CommandHandler? = null

    fun addListener(listener: Listener) {
        if (!listeners.contains(listener)) {
            listeners.add(listener)
        }
        listener.onEngineStateChanged(currentState)
    }

    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    fun updateState(transform: (State) -> State) {
        val newState = transform(currentState)
        if (newState != currentState) {
            currentState = newState
            for (listener in listeners) {
                try {
                    listener.onEngineStateChanged(newState)
                } catch (_: Exception) {}
            }
        }
    }

    fun requestStart(presetId: String? = null) {
        commandHandler?.onStartEngine(presetId ?: currentState.presetId)
    }

    fun requestStop() {
        commandHandler?.onStopEngine()
    }

    fun requestSetPreset(presetId: String) {
        updateState { it.copy(presetId = presetId) }
        commandHandler?.onSetPreset(presetId)
    }

    fun requestSetDriveMode(mode: Int) {
        updateState { it.copy(driveMode = mode) }
        commandHandler?.onSetDriveMode(mode)
    }

    fun requestSetAggressiveness(aggressiveness: Float) {
        updateState { it.copy(shiftAggressiveness = aggressiveness) }
        commandHandler?.onSetAggressiveness(aggressiveness)
    }
}
