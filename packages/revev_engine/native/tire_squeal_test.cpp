#include "tire_squeal_model.h"
#include "audio_mixer.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdlib>

void require(bool ok, const char *msg) {
    if (!ok) {
        std::fprintf(stderr, "FAIL: %s\n", msg);
        std::exit(1);
    }
}

int main() {
    TireSquealModel squeal;

    // 1. Procedural fallback initialization
    require(squeal.sampleCount() > 0, "Fallback samples must not be empty");
    require(!squeal.hasCustomWav(), "Should default to procedural fallback");

    // 2. Stationary test: zero vehicle speed mutes tire squeal even with extreme g-force
    squeal.updatePhysics(0.01f, 1.5f, 0.0f, 0.5f);
    require(squeal.targetVolume() == 0.0f, "Stationary high-g must not trigger squeal");
    for (int i = 0; i < 441; ++i) {
        require(squeal.processSample() == 0.0f, "Stationary sample must be 0");
    }

    // 3. Below threshold test: gentle cornering at normal driving speed produces no squeal
    // At sensitivity = 0.5, threshold is 0.95 - 0.70*0.5 = 0.60 g.
    squeal.updatePhysics(0.01f, 0.35f, 15.0f, 0.5f);
    require(squeal.targetVolume() == 0.0f, "Gentle cornering below threshold must not squeal");

    // 4. Moderate-to-hard cornering test: above threshold at speed generates squeal
    squeal.updatePhysics(0.01f, 0.85f, 15.0f, 0.5f);
    require(squeal.targetVolume() > 0.0f, "Hard cornering must produce target volume");
    require(squeal.intensity() > 0.0f, "Intensity must be positive");
    require(squeal.pitch() > 1.0f, "Pitch must rise above baseline under slip");

    // Process audio frames and check convergence and bounds
    float energy = 0.0f;
    for (int i = 0; i < 4410; ++i) { // 100 ms
        float s = squeal.processSample();
        require(std::isfinite(s), "Sample must be finite");
        require(std::abs(s) <= 1.0f, "Sample must be bounded within [-1, 1]");
        energy += s * s;
    }
    require(energy > 0.01f, "Hard cornering audio must have energy");
    require(squeal.volume() > 0.1f, "Current volume must have attacked toward target");

    // 5. Sensitivity scaling test
    // With high sensitivity (1.0), threshold drops to 0.25 g. A 0.40 g turn now triggers squeal.
    TireSquealModel highSens;
    highSens.updatePhysics(0.01f, 0.40f, 15.0f, 1.0f);
    require(highSens.targetVolume() > 0.0f, "High sensitivity must trigger at 0.40 g");

    // With low sensitivity (0.1), threshold is 0.88 g. A 0.40 g turn does not trigger.
    TireSquealModel lowSens;
    lowSens.updatePhysics(0.01f, 0.40f, 15.0f, 0.1f);
    require(lowSens.targetVolume() == 0.0f, "Low sensitivity must not trigger at 0.40 g");

    // With sensitivity = 0.0 (disabled), extreme turn triggers nothing
    TireSquealModel offSens;
    offSens.updatePhysics(0.01f, 1.5f, 25.0f, 0.0f);
    require(offSens.targetVolume() == 0.0f, "Zero sensitivity must disable squeal completely");

    // 6. AudioMixer 3-channel mix test
    const float mixedQuiet = AudioMixer::mix(0.3f, 0.1f, 0.1f);
    require(mixedQuiet == 0.5f, "Mixer below 0.70 threshold must be strictly linear");
    const float mixedLoud = AudioMixer::mix(0.8f, 0.5f, 0.4f);
    require(mixedLoud < AudioMixer::ceiling, "Mixer must soft compress below ceiling");

    // 7. Load converted WAV asset if available
    TireSquealModel wavModel;
    const std::string wavPath = "packages/revev_engine/assets/engine-sim/es/sound-library/new/tire_squeal.wav";
    bool loaded = wavModel.load(wavPath);
    if (loaded) {
        require(wavModel.hasCustomWav(), "Custom WAV flag must be set");
        require(wavModel.sampleCount() > 44100, "WAV should have multi-second sample loop");
        wavModel.updatePhysics(0.01f, 0.90f, 20.0f, 0.6f);
        float wavEnergy = 0.0f;
        for (int i = 0; i < 4410; ++i) {
            float s = wavModel.processSample();
            require(std::isfinite(s), "WAV sample must be finite");
            require(std::abs(s) <= 1.0f, "WAV sample must be bounded");
            wavEnergy += s * s;
        }
        require(wavEnergy > 0.01f, "Loaded WAV must produce audio energy");
        std::printf("Loaded WAV asset test passed (%zu samples)!\n", wavModel.sampleCount());
    } else {
        std::printf("WAV asset not found at relative path, verified procedural fallback.\n");
    }

    std::printf("All tire squeal DSP and sensitivity tests passed!\n");
    return 0;
}
