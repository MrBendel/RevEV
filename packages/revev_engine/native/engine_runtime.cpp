#include "engine_runtime.h"
#include "engine_preset.h"
#include "script_preset.h"
#include "preset_catalog.h"
#include "exhaust_response.h"
#include "listening_mix.h"
#include "output_limiter.h"
#include "turbo_model.h"
#include "audio_mixer.h"
#include "transmission_model.h"
#include "piston_engine_simulator.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <memory>

namespace {
class SessionSimulator : public PistonEngineSimulator {
public:
    ~SessionSimulator() {
        PistonEngineSimulator::destroy();
        Simulator::destroy();
    }
};
}

void EngineRuntime::start(const std::string &root, const std::string &preset) {
    const auto entry = presetEntry(preset);
    if (running_.exchange(true)) return;
    assetRoot_ = root; presetEntry_ = entry; presetId_ = preset; isTurbo_ = presetIsTurbo(preset);
    stopping_ = false; done_ = false; workMs_ = 0; gear_ = 0;
    read_ = 0; write_ = 0; underruns_ = 0; rpm_ = 0; boost_ = 0; failed_ = false; gain_ = 0;
    worker_ = std::thread(&EngineRuntime::run, this);
}
void EngineRuntime::stop() {
    running_ = false;
    if (worker_.joinable()) worker_.join();
    rpm_ = 0;
    boost_ = 0;
    gear_ = 0;
    speedMps_ = 0.0f;
    accelMps2_ = 0.0f;
}
void EngineRuntime::setThrottle(float v) {
    if (std::isfinite(v)) throttle_ = std::clamp(v, 0.0f, 1.0f);
}
void EngineRuntime::setVolume(float v) {
    if (std::isfinite(v)) volume_ = std::clamp(v, 0.0f, 1.0f);
}
void EngineRuntime::render(float *out, int frames) {
    auto r = read_.load(std::memory_order_relaxed);
    const auto w = write_.load(std::memory_order_acquire);
    const auto count = std::min<uint32_t>(w - r, frames);
    const float target = volume_.load(std::memory_order_relaxed);
    for (int i = 0; i < frames; ++i) {
        gain_ += (target - gain_) * 0.002f;
        out[i] = i < static_cast<int>(count) ? buffer_[(r + i) % capacity] * gain_ : 0;
    }
    read_.store(r + count, std::memory_order_release);
    if (!done_ && count < static_cast<uint32_t>(frames)) ++underruns_;
}
void EngineRuntime::run() {
    using clock = std::chrono::steady_clock;
    try {
        ScriptPreset preset(assetRoot_, presetEntry_);
        SessionSimulator sim;
        sim.initialize({Simulator::SystemType::NsvOptimized});
        sim.setSimulationFrequency(static_cast<int>(preset.engine->getSimulationFrequency()));
        sim.loadSimulation(preset.engine, preset.vehicle, preset.transmission);
        sim.setFluidSimulationSteps(8);
        for (int i = 0; i < preset.engine->getExhaustSystemCount(); ++i) {
            const auto *response = preset.engine->getExhaustSystem(i)->getImpulseResponse();
            if (response || !assetRoot_.empty()) {
                auto pcm = readExhaustResponse(response ? response->getFilename() :
                    assetRoot_ + "/es/sound-library/new/mild_exhaust.wav");
                sim.synthesizer().initializeImpulseResponse(pcm.data(), pcm.size(),
                    response ? response->getVolume() : 0.01, i);
            } else {
                // Standalone generic smoke tests without an asset directory.
                const int16_t impulse[] = {8192, 8192, 8192, 8191};
                sim.synthesizer().initializeImpulseResponse(impulse, 4, 1, i);
            }
        }
        auto audio = sim.synthesizer().getAudioParameters();
        audio.airNoise = presetEntry_.empty() ? 0.1f : preset.engine->getInitialNoise();
        audio.inputSampleNoise = presetEntry_.empty() ? 0.05f : preset.engine->getInitialJitter();
        audio.dF_F_mix = preset.engine->getInitialHighFrequencyGain();
        audio.levelerTarget = 12000;
        sim.synthesizer().setAudioParameters(audio);
        double elapsed = 0;
        bool started = false;
        // The heavy aircraft flywheels need a longer closed-throttle crank.
        const bool longCrank = presetEntry_ == "entries/atg-video-2/09_radial_9.mr" ||
            presetEntry_ == "entries/atg-video-2/11_merlin_v12.mr";
        const double crankTimeout = longCrank ? 12.0 : 5.0;
        double shutdownElapsed = 0, fadeElapsed = 0;
        bool fading = false;
        auto shutdownStarted = clock::time_point{};
        float filteredThrottle = 0;
        std::array<float, 441> pcm{};
        ListeningMix listeningMix;
        OutputLimiter limiter;
        TurboModel turboModel;
        turboModel.setEnabled(isTurbo_);
        TransmissionModel transmissionModel;
        try {
            const auto &p = getPreset(presetId_);
            transmissionModel.configure(p.gearCount, p.gearRatios, p.finalDrive,
                static_cast<float>(preset.engine->getRedline()), 900.0, 0.31);
        } catch (...) {
            const double defRatios[] = {3.5, 2.06, 1.41, 1.07, 0.86};
            transmissionModel.configure(5, defRatios, 3.44,
                static_cast<float>(preset.engine->getRedline()), 900.0, 0.31);
        }
        while (running_) {
            auto w = write_.load(std::memory_order_relaxed);
            if (w - read_.load(std::memory_order_acquire) >= 1323) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                continue;
            }
            const auto t = clock::now();
            const bool shuttingDown = stopping_.load();
            if (shuttingDown && shutdownStarted == clock::time_point{}) shutdownStarted = t;
            if (elapsed > 0.5 && preset.engine->getRpm() > 600) started = true;

            const int driveMode = driveMode_.load();
            const float speed = speedMps_.load();
            const float accel = accelMps2_.load();
            const float aggr = aggressiveness_.load();
            const float manualThr = throttle_.load();

            transmissionModel.update(0.01f, speed, accel, aggr, manualThr, driveMode);
            gear_ = transmissionModel.gear();

            float targetThrottle = 0.0f;
            if (shuttingDown) {
                targetThrottle = 0.0f;
                sim.m_dyno.m_enabled = false;
            } else if (driveMode == 0) {
                sim.m_dyno.m_enabled = false;
                targetThrottle = std::max(manualThr, !longCrank && !started && elapsed < crankTimeout ? 0.08f : 0.0f);
            } else {
                if (!started || elapsed < 1.2) {
                    sim.m_dyno.m_enabled = false;
                    targetThrottle = !longCrank && !started && elapsed < crankTimeout ? 0.08f : 0.0f;
                } else {
                    sim.m_dyno.m_enabled = true;
                    sim.m_dyno.m_hold = true;
                    sim.m_dyno.m_rotationSpeed = units::rpm(transmissionModel.targetRpm());
                    targetThrottle = transmissionModel.simulatedThrottle();
                }
            }

            filteredThrottle += (targetThrottle - filteredThrottle) * (driveMode > 0 ? 0.15f : 0.08f);
            preset.engine->setSpeedControl(filteredThrottle);
            preset.engine->getIgnitionModule()->m_enabled = !shuttingDown;
            sim.m_starterMotor.m_enabled = !shuttingDown && (elapsed < 1.5 || (!started && elapsed < crankTimeout));
            if (shuttingDown) shutdownElapsed += 0.01;
            sim.startFrame(0.01);
            while (sim.simulateStep()) {}
            sim.endFrame();
            // Upstream renderer is used synchronously on this worker. Its
            // mutexes and physics allocations never enter the audio callback.
            sim.synthesizer().renderAudio();
            sim.synthesizer().readAudioOutput(pcm.size(), pcm.data());
            const float rpm = static_cast<float>(preset.engine->getRpm());
            if (!std::isfinite(rpm) || std::abs(rpm) > 40000) { failed_ = true; break; }
            rpm_ = std::max(0.0f, rpm);
            turboModel.updatePhysics(0.01f, rpm, filteredThrottle, static_cast<float>(preset.engine->getRedline()));
            boost_ = turboModel.boostBar();
            if (shuttingDown && ((shutdownElapsed > 0.3 && std::abs(rpm) < 60) || shutdownElapsed >= 8 ||
                t - shutdownStarted >= std::chrono::seconds(8))) fading = true;
            const int mode = listeningMode_.load();
            const float strength = rumbleStrength_.load();
            for (uint32_t i = 0; i < pcm.size(); ++i) {
                const float fade = fading ? std::max(0.0, 1.0 - (fadeElapsed + i / 44100.0) / 0.2) : 1.0;
                if (!std::isfinite(pcm[i])) throw std::runtime_error("Non-finite engine audio");
                const float turboSound = turboModel.processSample();
                const float mixed = AudioMixer::mix(pcm[i], turboSound);
                const float shaped = listeningMix.process(mixed, mode, strength, filteredThrottle);
                buffer_[(w + i) % capacity] = limiter.process(AudioMixer::softCompress(shaped)) * fade;
            }
            write_.store(w + pcm.size(), std::memory_order_release);
            workMs_ = std::chrono::duration<float, std::milli>(clock::now() - t).count();
            elapsed += 0.01;
            if (fading) {
                fadeElapsed += 0.01;
                if (fadeElapsed >= 0.2) { done_ = true; break; }
            }
        }
    } catch (...) {
        failed_ = true;
    }
}
