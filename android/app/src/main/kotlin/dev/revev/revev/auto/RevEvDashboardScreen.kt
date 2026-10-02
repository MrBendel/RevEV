package dev.revev.revev.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import dev.revev.revev_engine.EngineBridge

class RevEvDashboardScreen(carContext: CarContext) : Screen(carContext), EngineBridge.Listener {
    private var engineState = EngineBridge.currentState

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onResume(owner: LifecycleOwner) {
                EngineBridge.addListener(this@RevEvDashboardScreen)
            }

            override fun onPause(owner: LifecycleOwner) {
                EngineBridge.removeListener(this@RevEvDashboardScreen)
            }
        })
    }

    override fun onEngineStateChanged(state: EngineBridge.State) {
        engineState = state
        invalidate()
    }

    private fun presetName(id: String): String {
        return EngineSelectScreen.PRESETS.firstOrNull { it.id == id }?.name
            ?: id.substringAfterLast("/").replace("_", " ").uppercase()
    }

    private fun driveModeLabel(mode: Int): String {
        return when (mode) {
            1 -> "GPS DRIVE"
            2 -> "SPEED SIM"
            else -> "MANUAL REV"
        }
    }

    private fun aggressivenessLabel(aggr: Float): String {
        return when {
            aggr < 0.35f -> "ECO (${(aggr * 100).toInt()}%)"
            aggr < 0.75f -> "SPORT (${(aggr * 100).toInt()}%)"
            else -> "RACE (${(aggr * 100).toInt()}%)"
        }
    }

    override fun onGetTemplate(): Template {
        val paneBuilder = Pane.Builder()

        // Row 1: Engine status & current preset
        val activeName = presetName(engineState.presetId)
        val statusText = if (engineState.playing) {
            "RUNNING · ${engineState.gearDisplay} · ${engineState.speedMph.toInt()} MPH (${engineState.speedKmh.toInt()} KM/H)"
        } else if (engineState.stopping) {
            "COASTING DOWN"
        } else {
            "ENGINE OFF · Tap Start to Crank"
        }

        paneBuilder.addRow(
            Row.Builder()
                .setTitle(activeName)
                .addText(statusText)
                .build()
        )

        // Row 2: Live RPM and boost telemetry
        val rpmTitle = if (engineState.playing) {
            "${engineState.rpm.toInt()} RPM"
        } else {
            "0 RPM · Stopped"
        }

        val telemetryText = if (engineState.boostBar > 0.02) {
            val boostFormatted = String.format("%.2f bar boost", engineState.boostBar)
            "$boostFormatted · Throttle: ${(engineState.throttle * 100).toInt()}%"
        } else {
            "Throttle: ${(engineState.throttle * 100).toInt()}% · Mode: ${driveModeLabel(engineState.driveMode)}"
        }

        paneBuilder.addRow(
            Row.Builder()
                .setTitle(rpmTitle)
                .addText(telemetryText)
                .build()
        )

        // Row 3: Drive Mode and transmission setting
        val modeTitle = "Transmission: ${driveModeLabel(engineState.driveMode)}"
        val modeSub = "Shift Aggressiveness: ${aggressivenessLabel(engineState.shiftAggressiveness)}"
        paneBuilder.addRow(
            Row.Builder()
                .setTitle(modeTitle)
                .addText(modeSub)
                .build()
        )

        // Primary Action: Start/Stop Engine
        val startStopAction = if (engineState.playing) {
            Action.Builder()
                .setTitle("STOP")
                .setBackgroundColor(CarColor.RED)
                .setOnClickListener { EngineBridge.requestStop() }
                .build()
        } else {
            Action.Builder()
                .setTitle("START")
                .setBackgroundColor(CarColor.GREEN)
                .setOnClickListener { EngineBridge.requestStart() }
                .build()
        }
        paneBuilder.addAction(startStopAction)

        // Secondary Action: Toggle Drive Mode
        paneBuilder.addAction(
            Action.Builder()
                .setTitle("MODE")
                .setOnClickListener {
                    val nextMode = (engineState.driveMode + 1) % 3
                    EngineBridge.requestSetDriveMode(nextMode)
                }
                .build()
        )

        // Header ActionStrip: Select Engine
        val actionStrip = ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setTitle("ENGINES")
                    .setOnClickListener {
                        screenManager.push(EngineSelectScreen(carContext))
                    }
                    .build()
            )
            .build()

        return PaneTemplate.Builder(paneBuilder.build())
            .setTitle("RevEV Dashboard")
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(actionStrip)
            .build()
    }
}
