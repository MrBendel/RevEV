#pragma once
#include <atomic>
#include <array>
#include <cstdint>
#include <thread>
#include <string>
#include <algorithm>
#include <cmath>

// Single producer (simulation worker), single consumer (audio callback).
// Lifecycle operations must be serialized by the platform adapter.
class EngineRuntime {
public:
    static constexpr int sampleRate = 44100;
    static constexpr uint32_t capacity = 8192;
    ~EngineRuntime() { stop(); }
    void start(const std::string &root = "", const std::string &preset = "generic");
    void shutdown() { stopping_ = true; throttle_ = 0; }
    bool stopping() const { return stopping_.load(); }
    bool finished() const { return done_.load() && read_.load() == write_.load(); }
    void stop();
    void setThrottle(float value);
    void setVolume(float value);
    void setListeningMix(int mode, float strength) {
        listeningMode_ = std::clamp(mode, 0, 2);
        if (std::isfinite(strength)) rumbleStrength_ = std::clamp(strength, 0.0f, 1.0f);
    }
    void render(float *out, int frames);
    float rpm() const { return rpm_.load(); }
    float workMs() const { return workMs_.load(); }
    uint32_t underruns() const { return underruns_.load(); }
    bool failed() const { return failed_.load(); }
private:
    void run();
    std::array<float, capacity> buffer_{};
    std::atomic<uint32_t> read_{0}, write_{0}, underruns_{0};
    std::atomic<float> throttle_{0}, volume_{0.15f}, rpm_{0}, workMs_{0};
    std::atomic<bool> running_{false}, failed_{false};
    std::atomic<int> listeningMode_{0};
    std::atomic<float> rumbleStrength_{0.5f};
    std::atomic<bool> stopping_{false}, done_{false};
    std::string assetRoot_, presetEntry_;
    float gain_ = 0; // audio-consumer owned; reset only while callback stopped
    std::thread worker_;
};
