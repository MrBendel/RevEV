#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

// TireSquealModel: Generates tire squealing audio driven by lateral g-force and vehicle speed.
// Uses a looped audio sample from an open source car racing game (or procedural fallback)
// with dynamic onset threshold, pitch modulation, and soft volume envelope.
class TireSquealModel {
public:
    static constexpr int sampleRate = 44100;

    TireSquealModel() {
        initProceduralFallback();
    }

    // Load 44.1 kHz PCM WAV audio file from asset path.
    // Falls back to procedural synthesis if file is missing or invalid.
    bool load(const std::string &path) {
        if (path.empty()) return false;
        std::ifstream input(path, std::ios::binary);
        if (!input) return false;

        auto u16 = [](const unsigned char *p) { return uint16_t(p[0] | (p[1] << 8)); };
        auto u32 = [](const unsigned char *p) {
            return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
        };

        unsigned char header[12];
        if (!input.read(reinterpret_cast<char*>(header), 12) ||
            std::memcmp(header, "RIFF", 4) != 0 ||
            std::memcmp(header + 8, "WAVE", 4) != 0) {
            return false;
        }

        int format = 0;
        int channels = 0;
        uint32_t rate = 0;
        int bits = 0;

        while (input) {
            unsigned char chunk[8];
            if (!input.read(reinterpret_cast<char*>(chunk), 8)) break;
            const uint32_t size = u32(chunk + 4);
            if (size > 32 * 1024 * 1024) break;

            if (!std::memcmp(chunk, "fmt ", 4)) {
                std::vector<unsigned char> fmt(size);
                if (size < 16 || !input.read(reinterpret_cast<char*>(fmt.data()), size)) break;
                format = u16(fmt.data());
                channels = u16(fmt.data() + 2);
                rate = u32(fmt.data() + 4);
                bits = u16(fmt.data() + 14);
            } else if (!std::memcmp(chunk, "data", 4) && bits > 0 && channels > 0) {
                const int bytesPerSample = bits / 8;
                if (bytesPerSample < 2) break;
                const size_t totalFrames = size / (channels * bytesPerSample);
                if (totalFrames == 0) break;

                std::vector<float> loaded;
                loaded.reserve(totalFrames);

                std::vector<unsigned char> frameBytes(channels * bytesPerSample);
                for (size_t f = 0; f < totalFrames; ++f) {
                    if (!input.read(reinterpret_cast<char*>(frameBytes.data()), frameBytes.size())) break;
                    float sum = 0.0f;
                    for (int ch = 0; ch < channels; ++ch) {
                        const unsigned char *p = frameBytes.data() + ch * bytesPerSample;
                        float val = 0.0f;
                        if (format == 1) { // PCM integer
                            if (bits == 16) {
                                int16_t s = static_cast<int16_t>(u16(p));
                                val = s / 32768.0f;
                            } else if (bits == 24) {
                                int32_t s = (static_cast<int32_t>(p[0]) << 8) |
                                            (static_cast<int32_t>(p[1]) << 16) |
                                            (static_cast<int32_t>(p[2]) << 24);
                                val = s / 2147483648.0f;
                            }
                        } else if (format == 3 && bits == 32) { // IEEE float
                            float fVal;
                            std::memcpy(&fVal, p, 4);
                            val = fVal;
                        }
                        sum += val;
                    }
                    loaded.push_back(sum / channels);
                }

                if (!loaded.empty()) {
                    samples_ = std::move(loaded);
                    hasCustomWav_ = true;
                    pos_ = 0.0;
                    return true;
                }
                break;
            } else {
                input.seekg(size, std::ios::cur);
            }
            if (size & 1) input.seekg(1, std::ios::cur);
        }
        return false;
    }

    // Update physical state and target sound parameters from vehicle telemetry.
    // lateralG: absolute lateral g-force (e.g. |a_lat| / 9.80665).
    // speedMps: current vehicle speed in meters per second.
    // sensitivity: user sensitivity setting in [0.0, 1.0].
    void updatePhysics(float dt, float lateralG, float speedMps, float sensitivity) {
        if (!std::isfinite(lateralG)) lateralG = 0.0f;
        if (!std::isfinite(speedMps)) speedMps = 0.0f;
        if (!std::isfinite(sensitivity)) sensitivity = 0.5f;

        lateralG = std::max(0.0f, lateralG);
        speedMps = std::max(0.0f, speedMps);
        sensitivity = std::clamp(sensitivity, 0.0f, 1.0f);

        // Speed gating: avoid squeal when stationary, creeping, or parking.
        // Full engagement at >= 6.0 m/s (~21 km/h or 13 mph).
        float speedFactor = 0.0f;
        if (speedMps >= 6.0f) {
            speedFactor = 1.0f;
        } else if (speedMps > 2.5f) {
            speedFactor = (speedMps - 2.5f) / 3.5f;
        }

        // Sensitivity slider sets onset threshold:
        // sensitivity = 1.0 -> onset at 0.25 g (highly sensitive / low threshold)
        // sensitivity = 0.5 -> onset at 0.60 g (balanced street threshold)
        // sensitivity = 0.1 -> onset at 0.88 g (track / heavy cornering only)
        // sensitivity = 0.0 -> disabled
        float rawIntensity = 0.0f;
        if (sensitivity > 0.01f) {
            const float thresholdG = 0.95f - 0.70f * sensitivity;
            if (lateralG > thresholdG) {
                rawIntensity = std::min(1.0f, (lateralG - thresholdG) / 0.35f);
            }
        }

        targetIntensity_ = rawIntensity * speedFactor;
        // Pitch rises slightly with cornering intensity (stick-slip frequency increase)
        targetPitch_ = 1.0f + 0.25f * rawIntensity;
        // Maximum squeal level scaled to sit harmoniously with engine PCM
        targetVolume_ = targetIntensity_ * 0.65f;
    }

    // Audio-rate sample generation (44.1 kHz).
    float processSample() {
        const float volStep = targetVolume_ > currentVolume_ ? 0.004f : 0.001f;
        currentVolume_ += (targetVolume_ - currentVolume_) * volStep;
        currentPitch_ += (targetPitch_ - currentPitch_) * 0.002f;

        if (currentVolume_ < 1e-5f) {
            return 0.0f;
        }
        if (samples_.empty()) {
            return 0.0f;
        }

        const size_t n = samples_.size();
        const size_t idx0 = static_cast<size_t>(pos_) % n;
        const size_t idx1 = (idx0 + 1) % n;
        const float frac = static_cast<float>(pos_ - static_cast<double>(idx0));
        const float sample = samples_[idx0] * (1.0f - frac) + samples_[idx1] * frac;

        pos_ += static_cast<double>(currentPitch_);
        if (pos_ >= static_cast<double>(n)) {
            pos_ -= static_cast<double>(n);
        }

        return sample * currentVolume_;
    }

    float volume() const { return currentVolume_; }
    float targetVolume() const { return targetVolume_; }
    float intensity() const { return targetIntensity_; }
    float pitch() const { return currentPitch_; }
    bool hasCustomWav() const { return hasCustomWav_; }
    size_t sampleCount() const { return samples_.size(); }

    void reset() {
        pos_ = 0.0;
        currentVolume_ = 0.0f;
        targetVolume_ = 0.0f;
        currentPitch_ = 1.0f;
        targetPitch_ = 1.0f;
        targetIntensity_ = 0.0f;
    }

private:
    void initProceduralFallback() {
        hasCustomWav_ = false;
        // Synthesize 1-second seamless looping resonant tire slip tone for headless tests
        constexpr int count = sampleRate;
        samples_.resize(count);
        for (int i = 0; i < count; ++i) {
            const double t = static_cast<double>(i) / sampleRate;
            // Mix of fundamental tire friction tones (850 Hz, 1200 Hz, 1750 Hz) with pseudo-noise
            const double f1 = std::sin(2.0 * 3.141592653589793 * 850.0 * t);
            const double f2 = std::sin(2.0 * 3.141592653589793 * 1200.0 * t) * 0.5;
            const double f3 = std::sin(2.0 * 3.141592653589793 * 1750.0 * t) * 0.25;
            // Deterministic pseudo-random noise
            const uint32_t seed = static_cast<uint32_t>(i * 1664525u + 1013904223u);
            const float noise = (static_cast<float>(seed & 0xFFFF) / 32768.0f - 1.0f) * 0.2f;
            samples_[i] = static_cast<float>((f1 + f2 + f3) * 0.3 + noise);
        }
    }

    std::vector<float> samples_;
    double pos_ = 0.0;
    float currentVolume_ = 0.0f;
    float targetVolume_ = 0.0f;
    float currentPitch_ = 1.0f;
    float targetPitch_ = 1.0f;
    float targetIntensity_ = 0.0f;
    bool hasCustomWav_ = false;
};
