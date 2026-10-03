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
    void start(const std::string &root = "", const std::string &preset = "porsche/911_carrera_32");
    void shutdown() { stopping_ = true; throttle_ = 0; }
    bool stopping() const { return stopping_.load(); }
    bool finished() const { return done_.load() && read_.load() == write_.load(); }
    uint32_t availableFrames() const {
        const auto w = write_.load(std::memory_order_acquire);
        const auto r = read_.load(std::memory_order_relaxed);
        return w > r ? (w - r) : 0;
    }
    bool isReadyToRender() const { return availableFrames() >= 441; }
    void stop();
    void setThrottle(float value);
    void setVolume(float value);
    void setListeningMix(int mode, float strength) {
        listeningMode_ = std::clamp(mode, 0, 2);
        if (std::isfinite(strength)) rumbleStrength_ = std::clamp(strength, 0.0f, 1.0f);
    }
    void setDriveTelemetry(float speedMps, float accelMps2, float aggressiveness, int driveMode,
                           float lateralAccelMps2 = 0.0f, float tireSquealSensitivity = 0.5f) {
        if (std::isfinite(speedMps)) speedMps_ = std::max(0.0f, speedMps);
        if (std::isfinite(accelMps2)) accelMps2_ = accelMps2;
        if (std::isfinite(aggressiveness)) aggressiveness_ = std::clamp(aggressiveness, 0.0f, 1.0f);
        driveMode_ = std::clamp(driveMode, 0, 2);
        if (std::isfinite(lateralAccelMps2)) lateralAccelMps2_ = std::abs(lateralAccelMps2);
        if (std::isfinite(tireSquealSensitivity)) tireSquealSensitivity_ = std::clamp(tireSquealSensitivity, 0.0f, 1.0f);
    }
    void setTireSqueal(float lateralAccelMps2, float sensitivity) {
        if (std::isfinite(lateralAccelMps2)) lateralAccelMps2_ = std::abs(lateralAccelMps2);
        if (std::isfinite(sensitivity)) tireSquealSensitivity_ = std::clamp(sensitivity, 0.0f, 1.0f);
    }
    void render(float *out, int frames);
    float rpm() const { return rpm_.load(); }
    float boost() const { return boost_.load(); }
    float workMs() const { return workMs_.load(); }
    uint32_t underruns() const { return underruns_.load(); }
    bool failed() const { return failed_.load(); }
    int gear() const { return gear_.load(); }
    float vehicleSpeed() const { return speedMps_.load(); }
    int driveMode() const { return driveMode_.load(); }
    float lateralAccel() const { return lateralAccelMps2_.load(); }
    float tireSquealSensitivity() const { return tireSquealSensitivity_.load(); }
    float tireSquealLevel() const { return tireSquealLevel_.load(); }
private:
    void run();
    std::array<float, capacity> buffer_{};
    std::atomic<uint32_t> read_{0}, write_{0}, underruns_{0};
    std::atomic<float> throttle_{0}, volume_{0.15f}, rpm_{0}, workMs_{0}, boost_{0};
    std::atomic<float> speedMps_{0.0f}, accelMps2_{0.0f}, aggressiveness_{0.5f};
    std::atomic<float> lateralAccelMps2_{0.0f}, tireSquealSensitivity_{0.5f}, tireSquealLevel_{0.0f};
    std::atomic<int> driveMode_{0}, gear_{0};
    std::atomic<bool> running_{false}, failed_{false};
    std::atomic<int> listeningMode_{0};
    std::atomic<float> rumbleStrength_{0.5f};
    std::atomic<bool> stopping_{false}, done_{false};
    std::string assetRoot_, presetEntry_, presetId_;
    bool isTurbo_ = false;
    float gain_ = 0; // audio-consumer owned; reset only while callback stopped
    std::thread worker_;
};
