#include "turbo_model.h"
#include <cassert>
#include <cmath>
#include <cstdio>

int main() {
    TurboModel turbo;

    // 1. Naturally aspirated test: disabled produces exactly 0 boost and 0 audio
    turbo.setEnabled(false);
    turbo.updatePhysics(0.01f, 4000.0f, 0.8f, 7000.0f);
    assert(turbo.boostBar() == 0.0f);
    for (int i = 0; i < 441; ++i) {
        assert(turbo.processSample() == 0.0f);
    }

    // 2. Turbo spool test: enabled builds boost under load
    turbo.setEnabled(true);
    for (int frame = 0; frame < 100; ++frame) {
        turbo.updatePhysics(0.01f, 4500.0f, 0.9f, 7000.0f);
    }
    const float boost = turbo.boostBar();
    std::printf("Spool boost after 1s: %.2f bar\n", boost);
    assert(boost > 0.5f && boost <= 1.5f);

    // Audio output must be nonzero, finite and bounded
    float energy = 0.0f;
    for (int i = 0; i < 4410; ++i) {
        float sample = turbo.processSample();
        assert(std::isfinite(sample));
        assert(std::abs(sample) <= 1.0f);
        energy += sample * sample;
    }
    assert(energy > 0.001f);

    // 3. Blow-Off Valve (BOV) test: abrupt lift-off triggers "psssst"
    turbo.updatePhysics(0.01f, 4500.0f, 0.0f, 7000.0f);
    float bovEnergy = 0.0f;
    float peak = 0.0f;
    for (int i = 0; i < 4410; ++i) { // 100 ms
        float sample = turbo.processSample();
        assert(std::isfinite(sample));
        assert(std::abs(sample) <= 1.0f);
        bovEnergy += sample * sample;
        peak = std::max(peak, std::abs(sample));
    }
    std::printf("BOV energy: %.4f, peak: %.4f\n", bovEnergy, peak);
    assert(bovEnergy > 0.01f);
    assert(peak > 0.05f);

    // 4. Boost vents and decays
    for (int frame = 0; frame < 60; ++frame) {
        turbo.updatePhysics(0.01f, 2000.0f, 0.0f, 7000.0f);
    }
    std::printf("Boost after BOV vent: %.2f bar\n", turbo.boostBar());
    assert(turbo.boostBar() < 0.2f);

    std::printf("All turbo DSP checks passed!\n");
    return 0;
}
