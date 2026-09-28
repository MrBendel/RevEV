#pragma once
#include <atomic>
#include <array>
#include <cstdint>
#include <thread>

// Single producer (simulation worker), single consumer (audio callback).
// Lifecycle operations must be serialized by the platform adapter.
class EngineRuntime {
public:
    static constexpr int sampleRate = 44100;
    static constexpr uint32_t capacity = 8192;
    ~EngineRuntime() { stop(); }
    void start();
    void stop();
    void setThrottle(float value);
    void setVolume(float value);
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
    float gain_ = 0; // audio-consumer owned; reset only while callback stopped
    std::thread worker_;
};
