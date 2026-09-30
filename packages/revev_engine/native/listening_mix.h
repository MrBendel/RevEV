#pragma once
#include <algorithm>
#include <cmath>

// Fixed resonators excited by simulated exhaust preserve the firing rhythm.
// No allocation, locks, or independent oscillator; called on the native worker.
class ListeningMix {
    struct Biquad {
        double b0, b1, b2, a1, a2, z1 = 0, z2 = 0;
        float process(float x) {
            const double y = b0*x + z1;
            z1 = b1*x - a1*y + z2; z2 = b2*x - a2*y;
            return static_cast<float>(y);
        }
        static Biquad make(double hz, double q, bool band) {
            const double w = 6.283185307179586*hz/44100, c = std::cos(w);
            const double a = std::sin(w)/(2*q), d = 1+a;
            return band ? Biquad{a/d, 0, -a/d, -2*c/d, (1-a)/d} :
                Biquad{(1-c)/(2*d), (1-c)/d, (1-c)/(2*d), -2*c/d, (1-a)/d};
        }
    };
    Biquad cabin_ = Biquad::make(1400, .707, false);
    Biquad body_ = Biquad::make(95, .8, true);
    Biquad low_ = Biquad::make(65, 1.4, true);
    Biquad upper_ = Biquad::make(110, 1.1, true);
    float wet_ = 0, rumble_ = 0, strength_ = .5f, load_ = 0;
    double dryPower_ = 0, cabinPower_ = 0, rumblePower_ = 0;
    float cabinGain_ = 1, rumbleGain_ = 1;
public:
    // Original stays exact. Slow, bounded RMS matching approximates equal level,
    // not perceptual loudness. Throttle is a temporary proxy for engine load.
    float process(float dry, int mode, float strength, float throttle) {
        constexpr float smooth = 1.0f/(44100*.05f);
        wet_ += ((mode == 0 ? 0.0f : 1.0f)-wet_)*smooth;
        rumble_ += ((mode == 2 ? 1.0f : 0.0f)-rumble_)*smooth;
        strength_ += (strength-strength_)*smooth;
        load_ += (throttle-load_)*smooth;
        const float cabin = cabin_.process(dry) + .6f*body_.process(dry);
        const float bass = .7f*low_.process(dry) + .3f*upper_.process(dry);
        const float enhanced = cabin + bass*strength_*(.6f+1.4f*load_);
        constexpr double rate = 1.0/(44100*.25);
        dryPower_ += (dry*dry-dryPower_)*rate;
        cabinPower_ += (cabin*cabin-cabinPower_)*rate;
        rumblePower_ += (enhanced*enhanced-rumblePower_)*rate;
        const auto gain = [this](double power) {
            return dryPower_ < 1e-8 ? 1.0f : static_cast<float>(
                std::clamp(std::sqrt(dryPower_/std::max(power, 1e-8)), .25, 2.0));
        };
        cabinGain_ += (gain(cabinPower_)-cabinGain_)*.00005f;
        rumbleGain_ += (gain(rumblePower_)-rumbleGain_)*.00005f;
        const float processed = cabin*cabinGain_*(1-rumble_) + enhanced*rumbleGain_*rumble_;
        const float peak = std::abs(processed);
        const float limited = peak <= .8f ? processed : std::copysign(
            .8f + .2f*(peak-.8f)/(.2f+peak-.8f), processed);
        return dry + wet_*(limited-dry);
    }
};
