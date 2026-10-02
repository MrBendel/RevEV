#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

// Authentic turbocharger spool hiss/whistle and blow-off valve (BOV) simulation.
// Uses filtered aerodynamic air turbulence and blade-pass resonance rather than
// artificial sine-wave synthesis to prevent electrical whine.
class TurboModel {
public:
    void reset() {
        boost_ = 0.0f;
        targetBoost_ = 0.0f;
        spoolRpm_ = 0.0f;
        bovActive_ = false;
        bovTimer_ = 0.0f;
        bovPressure_ = 0.0f;
        prevThrottle_ = 0.0f;
        noiseSeed_ = 123456789;
        w_x1_ = 0.0f;
        w_x2_ = 0.0f;
        w_y1_ = 0.0f;
        w_y2_ = 0.0f;
        b_x1_ = 0.0f;
        b_x2_ = 0.0f;
        b_y1_ = 0.0f;
        b_y2_ = 0.0f;
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
        if (!enabled) reset();
    }
    bool isEnabled() const { return enabled_; }

    float boostBar() const { return boost_; }

    // Called once per 10ms physics block
    void updatePhysics(float dt, float engineRpm, float throttle, float redline) {
        if (!enabled_) {
            boost_ = 0.0f;
            return;
        }

        // Throttle drop detection for Blow-Off Valve (BOV)
        if (throttle < 0.15f && prevThrottle_ > 0.30f && boost_ > 0.18f && !bovActive_) {
            bovActive_ = true;
            bovTimer_ = 0.0f;
            bovPressure_ = boost_;
        }
        prevThrottle_ = throttle;

        // Target boost calculation: builds with RPM and throttle above 2000 RPM
        const float rpmNorm = std::clamp((engineRpm - 2000.0f) / 2200.0f, 0.0f, 1.0f);
        if (bovActive_) {
            targetBoost_ = 0.0f;
            boost_ += (0.0f - boost_) * std::clamp(dt * 8.0f, 0.0f, 1.0f);
            bovTimer_ += dt;
            if (bovTimer_ > 0.55f) {
                bovActive_ = false;
            }
        } else {
            const float maxBoost = 1.10f; // ~1.1 bar (16 psi) peak boost
            targetBoost_ = (throttle > 0.05f) ? (std::pow(throttle, 1.2f) * rpmNorm * maxBoost) : 0.0f;
            const float rate = (targetBoost_ > boost_) ? 3.5f : 5.0f;
            boost_ += (targetBoost_ - boost_) * std::clamp(dt * rate, 0.0f, 1.0f);
        }

        boost_ = std::clamp(boost_, 0.0f, 1.5f);
        spoolRpm_ += ((boost_ / 1.10f) - spoolRpm_) * std::clamp(dt * 4.0f, 0.0f, 1.0f);
        spoolRpm_ = std::clamp(spoolRpm_, 0.0f, 1.2f);
    }

    // Process a single audio sample at 44.1 kHz
    float processSample() {
        if (!enabled_) return 0.0f;

        // Fast pseudo-random white noise generator
        noiseSeed_ = (1103515245U * noiseSeed_ + 12345U);
        const float noise = static_cast<float>(static_cast<int32_t>(noiseSeed_)) * (1.0f / 2147483648.0f);

        // 1. Compressor spool whistle & aerodynamic air rush (RBJ Bandpass filter)
        // Blade-pass resonance sweeps from 1500 Hz to 3800 Hz with turbine spool
        const float bpfFreq = 1500.0f + 2300.0f * spoolRpm_;
        const float w0 = 2.0f * 3.14159265f * (bpfFreq / 44100.0f);
        const float q = 6.0f;
        const float alpha = std::sin(w0) / (2.0f * q);
        const float b0 = alpha;
        const float b1 = 0.0f;
        const float b2 = -alpha;
        const float a0 = 1.0f + alpha;
        const float a1 = -2.0f * std::cos(w0);
        const float a2 = 1.0f - alpha;

        const float whistle = (b0 * noise + b1 * w_x1_ + b2 * w_x2_ - a1 * w_y1_ - a2 * w_y2_) / a0;
        w_x2_ = w_x1_;
        w_x1_ = noise;
        w_y2_ = w_y1_;
        w_y1_ = whistle;

        const float airRush = noise * 0.25f;
        const float spoolGain = (spoolRpm_ * 0.08f) + (boost_ * 0.05f);
        const float spoolAudio = (whistle * 0.65f + airRush * 0.35f) * spoolGain;

        // 2. Blow-Off Valve (BOV) venting ("psssst!" with surge flutter)
        float bovAudio = 0.0f;
        if (bovActive_ && bovTimer_ < 0.50f) {
            const float env = std::exp(-bovTimer_ * 8.5f);
            const float flutter = 1.0f + 0.25f * std::sin(2.0f * 3.14159265f * 18.0f * bovTimer_);

            const float bovW0 = 2.0f * 3.14159265f * (2600.0f / 44100.0f);
            const float bovAlpha = std::sin(bovW0) / (2.0f * 2.5f);
            const float bb0 = bovAlpha;
            const float bb1 = 0.0f;
            const float bb2 = -bovAlpha;
            const float ba0 = 1.0f + bovAlpha;
            const float ba1 = -2.0f * std::cos(bovW0);
            const float ba2 = 1.0f - bovAlpha;

            const float bovFiltered = (bb0 * noise + bb1 * b_x1_ + bb2 * b_x2_ - ba1 * b_y1_ - ba2 * b_y2_) / ba0;
            b_x2_ = b_x1_;
            b_x1_ = noise;
            b_y2_ = b_y1_;
            b_y1_ = bovFiltered;

            bovAudio = bovFiltered * env * flutter * (bovPressure_ * 0.20f);
        }

        return spoolAudio + bovAudio;
    }

private:
    bool enabled_ = false;
    float boost_ = 0.0f;
    float targetBoost_ = 0.0f;
    float spoolRpm_ = 0.0f;
    bool bovActive_ = false;
    float bovTimer_ = 0.0f;
    float bovPressure_ = 0.0f;
    float prevThrottle_ = 0.0f;
    uint32_t noiseSeed_ = 123456789;
    float w_x1_ = 0.0f, w_x2_ = 0.0f, w_y1_ = 0.0f, w_y2_ = 0.0f;
    float b_x1_ = 0.0f, b_x2_ = 0.0f, b_y1_ = 0.0f, b_y2_ = 0.0f;
};
