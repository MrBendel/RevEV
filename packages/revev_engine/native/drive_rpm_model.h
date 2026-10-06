#pragma once
#include <algorithm>
#include <cmath>

// Kinematic RPM trajectory. No measured engine RPM or throttle feedback.
// Gear/speed determine the destination; bounded slew handles shifts and GPS steps.
class DriveRpmModel {
public:
    void reset() { initialized_ = false; }
    float update(float dt, float target) {
        if (!std::isfinite(target)) target = 900.0f;
        target = std::clamp(target, 0.0f, 40000.0f);
        if (!initialized_) { rpm_ = target; initialized_ = true; }
        if (std::isfinite(dt) && dt > 0) {
            const float step = 6000.0f * std::min(dt, 0.1f);
            rpm_ += std::clamp(target - rpm_, -step, step);
        }
        return rpm_;
    }
private:
    bool initialized_ = false;
    float rpm_ = 900.0f;
};
