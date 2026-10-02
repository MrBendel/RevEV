package dev.revev.revev.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import dev.revev.revev_engine.EngineBridge

class EngineSelectScreen(carContext: CarContext) : Screen(carContext) {

    data class PresetInfo(
        val id: String,
        val name: String,
        val description: String
    )

    companion object {
        val PRESETS = listOf(
            PresetInfo("porsche/911_carrera_32", "Porsche 911 Carrera 3.2", "3.2L Flat-6 NA · 8,000 RPM · 5-Speed"),
            PresetInfo("porsche/911_turbo_33", "Porsche 911 Turbo 3.3", "3.3L Flat-6 Turbo · 8,000 RPM · 4-Speed"),
            PresetInfo("atg-video-1/05_honda_vtec", "Honda B18C5 VTEC", "1.8L Inline-4 NA · 8,800 RPM · 5-Speed"),
            PresetInfo("atg-video-2/08_ferrari_f136_v8", "Ferrari F136 V8", "4.5L Flat-Plane V8 · 12,000 RPM · 7-Speed DCT"),
            PresetInfo("atg-video-2/07_gm_ls", "GM LS V8", "5.7L Pushrod V8 · 7,500 RPM · 6-Speed"),
            PresetInfo("atg-video-2/03_2jz", "Toyota 2JZ-GTE", "3.0L Twin-Turbo Inline-6 · 8,500 RPM · 6-Speed"),
            PresetInfo("atg-video-2/10_lfa_v10", "Lexus 1LR-GUE V10", "4.8L Screaming V10 · 10,000 RPM · 6-Speed"),
            PresetInfo("subaru/ej25_sti", "Subaru EJ25 STI", "2.5L Turbo Boxer-4 · 7,500 RPM · 6-Speed")
        )
    }

    override fun onGetTemplate(): Template {
        val listBuilder = ItemList.Builder()
        val currentPreset = EngineBridge.currentState.presetId

        for (preset in PRESETS) {
            val isCurrent = preset.id == currentPreset
            val title = if (isCurrent) "✓ ${preset.name}" else preset.name
            val row = Row.Builder()
                .setTitle(title)
                .addText(preset.description)
                .setOnClickListener {
                    EngineBridge.requestSetPreset(preset.id)
                    screenManager.pop()
                }
                .build()
            listBuilder.addItem(row)
        }

        return ListTemplate.Builder()
            .setTitle("Select Engine")
            .setHeaderAction(Action.BACK)
            .setSingleList(listBuilder.build())
            .build()
    }
}
