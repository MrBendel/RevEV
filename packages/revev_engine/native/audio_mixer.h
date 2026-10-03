#pragma once
#include <algorithm>
#include <cmath>

// AudioMixer: Mixes synthesized engine simulation PCM and auxiliary audio sources
// (such as turbocharger spool and blow-off valve) with soft compression (smooth knee
// saturation curve) to prevent digital clipping, distortion, and limiter pumping.
class AudioMixer {
public:
    static constexpr float threshold = 0.70f; // Linear transparency region
    static constexpr float ceiling = 0.88f;   // Maximum asymptote below limiter ceiling

    // Smooth rational soft knee compression curve with C1 continuity.
    // Passes signals up to threshold (0.70) completely linearly without coloring.
    // Compresses higher transient peaks smoothly toward ceiling (0.88).
    static inline float softCompress(float x) {
        if (!std::isfinite(x)) return 0.0f;
        const float absX = std::abs(x);
        if (absX <= threshold) return x;
        const float excess = absX - threshold;
        constexpr float range = ceiling - threshold;
        const float compressed = threshold + range * (excess / (range + excess));
        return std::copysign(compressed, x);
    }

    // Mix engine PCM, turbo sound, and tire squeal with soft compression
    static inline float mix(float engine, float turbo, float squeal = 0.0f) {
        if (!std::isfinite(engine)) engine = 0.0f;
        if (!std::isfinite(turbo)) turbo = 0.0f;
        if (!std::isfinite(squeal)) squeal = 0.0f;
        const float combined = engine + turbo + squeal;
        return softCompress(combined);
    }
};
