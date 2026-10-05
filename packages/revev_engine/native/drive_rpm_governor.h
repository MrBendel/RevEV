#pragma once
#include <algorithm>
#include <cmath>

// Throttle-only speed control. Damping uses measured RPM (not target changes),
// and integral trim learns the throttle required by each engine at cruise.
class DriveRpmGovernor {
public:
    void reset() { initialized_ = false; trim_ = slope_ = feedForward_ = 0.0f; }

    float update(float dt, float targetRpm, float rpm, float demand, bool shifting) {
        if (!std::isfinite(dt) || dt <= 0.0f || !std::isfinite(targetRpm) ||
            !std::isfinite(rpm) || !std::isfinite(demand)) {
            reset();
            return 0.0f;
        }
        dt = std::min(dt, 0.05f);
        demand = std::clamp(demand, 0.0f, 1.0f);
        // Estimate cruise throttle from desired speed, not each acceleration
        // pulse. Acceleration already affects launch RPM and gear selection.
        // Feeding it into throttle again fights the speed loop on rough mounts.
        const float base = std::clamp(0.07f + (targetRpm - 1500.0f) * 0.00004f, 0.0f, 0.30f);
        if (!initialized_) {
            filteredRpm_ = rpm;
            feedForward_ = base;
            initialized_ = true;
        }
        const float previousRpm = filteredRpm_;
        filteredRpm_ += (rpm - filteredRpm_) * dt / (0.10f + dt);
        const float measuredSlope = (filteredRpm_ - previousRpm) / dt;
        slope_ += (measuredSlope - slope_) * dt / (0.15f + dt);
        feedForward_ += (base - feedForward_) * dt / (0.20f + dt);
        if (shifting) return demand; // Preserve deliberate torque cuts/rev blips.

        const float error = targetRpm - filteredRpm_;
        const float correction = error * 0.00010f - slope_ * 0.000025f;
        const float candidateTrim = std::clamp(trim_ + error * dt * 0.00003f, -0.35f, 0.70f);
        const float candidate = feedForward_ + correction + candidateTrim;
        // Do not wind up against the throttle stops, including unattainable
        // targets below an engine's natural idle speed.
        if ((candidate >= 0.0f && candidate <= 1.0f) ||
            (candidate < 0.0f && error > 0.0f) ||
            (candidate > 1.0f && error < 0.0f)) trim_ = candidateTrim;
        return std::clamp(feedForward_ + correction + trim_, 0.0f, 1.0f);
    }

private:
    bool initialized_ = false;
    float filteredRpm_ = 0.0f, slope_ = 0.0f, trim_ = 0.0f, feedForward_ = 0.0f;
};
