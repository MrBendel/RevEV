#include "engine_runtime.h"
#include "engine_preset.h"
#include "piston_engine_simulator.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <memory>

void EngineRuntime::start() {
    if (running_.exchange(true)) return;
    read_ = 0; write_ = 0; underruns_ = 0; rpm_ = 0; failed_ = false; gain_ = 0;
    worker_ = std::thread(&EngineRuntime::run, this);
}
void EngineRuntime::stop() {
    running_ = false;
    if (worker_.joinable()) worker_.join();
    rpm_ = 0;
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
    if (count < static_cast<uint32_t>(frames)) ++underruns_;
}
void EngineRuntime::run() {
    using clock = std::chrono::steady_clock;
    try {
        EnginePreset preset;
        PistonEngineSimulator sim;
        sim.initialize({Simulator::SystemType::NsvOptimized});
        sim.loadSimulation(&preset.engine, &preset.vehicle, &preset.transmission);
        sim.setSimulationFrequency(10000);
        sim.setFluidSimulationSteps(8);
        // Identity impulse: no external recording / impulse-response license.
        const int16_t impulse[] = {32767};
        sim.synthesizer().initializeImpulseResponse(impulse, 1, 1, 0);
        auto audio = sim.synthesizer().getAudioParameters();
        audio.airNoise = 0.2f; audio.inputSampleNoise = 0.1f;
        audio.levelerTarget = 12000;
        sim.synthesizer().setAudioParameters(audio);
        double elapsed = 0;
        float filteredThrottle = 0;
        std::array<int16_t, 441> pcm{};
        while (running_) {
            auto w = write_.load(std::memory_order_relaxed);
            if (w - read_.load(std::memory_order_acquire) >= 1323) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                continue;
            }
            const auto t = clock::now();
            filteredThrottle += (throttle_.load() - filteredThrottle) * 0.08f;
            preset.engine.setSpeedControl(filteredThrottle);
            sim.m_starterMotor.m_enabled = elapsed < 1.5;
            sim.startFrame(0.01);
            while (sim.simulateStep()) {}
            sim.endFrame();
            // Upstream renderer is used synchronously on this worker. Its
            // mutexes and physics allocations never enter the audio callback.
            sim.synthesizer().renderAudio();
            sim.readAudioOutput(pcm.size(), pcm.data());
            const float rpm = static_cast<float>(preset.engine.getRpm());
            if (!std::isfinite(rpm) || rpm > 12000) { failed_ = true; break; }
            rpm_ = rpm;
            for (uint32_t i = 0; i < pcm.size(); ++i) buffer_[(w + i) % capacity] = pcm[i] / 32768.0f;
            write_.store(w + pcm.size(), std::memory_order_release);
            workMs_ = std::chrono::duration<float, std::milli>(clock::now() - t).count();
            elapsed += 0.01;
        }
        sim.destroy();
        sim.Simulator::destroy();
    } catch (...) {
        failed_ = true;
    }
}
