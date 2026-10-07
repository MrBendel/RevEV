#pragma once

// Callback-owned state. A starvation tail survives callback boundaries, then
// crossfades into fresh PCM. No allocation, waiting, or resetting to zero clicks.
class OutputContinuity {
public:
    float process(float sample, bool available) {
        if (!available) {
            starved_ = true;
            remaining_ = 128;
            last_ *= 0.995f;
            if (last_ < 1e-8f && last_ > -1e-8f) last_ = 0;
            return last_;
        }
        if (starved_) { anchor_ = last_; starved_ = false; }
        if (remaining_ > 0) {
            const float blend = 1.0f - static_cast<float>(--remaining_) / 128.0f;
            sample = anchor_ * (1.0f - blend) + sample * blend;
        }
        return last_ = sample;
    }
private:
    float last_ = 0, anchor_ = 0;
    int remaining_ = 128;
    bool starved_ = true;
};
