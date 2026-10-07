#pragma once
#include <algorithm>
#include <cmath>

// Bounded makeup compression, before the existing lookahead peak limiter.
// Up to +6 dB for quiet passages, 3:1 above -12 dBFS RMS with a 6 dB knee.
// Never attenuates an already loud passage relative to the original signal.
// 30 ms RMS detector, 10 ms gain reduction, 250 ms recovery; no allocations.
class LoudnessCompressor {
public:
    float process(float input) {
        if (!std::isfinite(input)) input = 0;
        input = std::clamp(input, -16.0f, 16.0f);
        power_ += (static_cast<double>(input) * input - power_) * detector_;
        if (++samples_ == 64) {
            samples_ = 0;
            const double over = 10.0 * std::log10(std::max(power_, 1e-12)) + 12.0;
            const double reduction = over <= -3 ? 0 : over >= 3 ? over * (2.0 / 3.0)
                : (over + 3) * (over + 3) / 18.0;
            target_ = static_cast<float>(std::pow(10.0, std::clamp(6.0 - reduction, 0.0, 6.0) / 20.0));
        }
        gain_ += (target_ - gain_) * (target_ < gain_ ? attack_ : release_);
        return input * gain_;
    }
private:
    double power_ = 0;
    float gain_ = 1, target_ = 1;
    int samples_ = 0;
    const double detector_ = 1.0 - std::exp(-1.0 / (44100 * .030));
    const float attack_ = 1.0f - std::exp(-1.0f / (44100 * .010f));
    const float release_ = 1.0f - std::exp(-1.0f / (44100 * .250f));
};
