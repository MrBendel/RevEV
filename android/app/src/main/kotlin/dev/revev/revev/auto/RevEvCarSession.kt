package dev.revev.revev.auto

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class RevEvCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return RevEvDashboardScreen(carContext)
    }
}
