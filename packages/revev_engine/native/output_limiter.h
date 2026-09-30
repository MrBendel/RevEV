#pragma once
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdint>

// Sample-peak limiter after the listening mix, before fade and user volume.
// 5 ms lookahead, immediate gain reduction, 100 ms exponential recovery.
// The sliding peak window holds reduction through an entire transient instead
// of flattening each sample. Fixed storage, amortized O(1), worker thread only.
class OutputLimiter {
public:
    static constexpr int delay = 220;
    static constexpr float ceiling = .89f; // about -1 dBFS sample-peak headroom
    float process(float input) {
        if (!std::isfinite(input)) input = 0;
        const float output = audio_[index_ % delay];
        audio_[index_ % delay] = input;
        while (size_ && peaks_[head_].index + delay < index_) pop();
        const float peak = std::abs(input);
        while (size_ && peaks_[(head_ + size_ - 1) % capacity].value <= peak) --size_;
        peaks_[(head_ + size_) % capacity] = {index_, peak};
        ++size_;
        const float maximum = peaks_[head_].value;
        const float target = maximum > ceiling ? ceiling / maximum : 1.0f;
        gain_ = std::min(target, gain_ + (1.0f - gain_) * release_);
        ++index_;
        return output * gain_;
    }
private:
    struct Peak { uint64_t index = 0; float value = 0; };
    static constexpr int capacity = delay + 1;
    std::array<float, delay> audio_{};
    std::array<Peak, capacity> peaks_{};
    uint64_t index_ = 0;
    int head_ = 0, size_ = 0;
    float gain_ = 1;
    const float release_ = 1.0f - std::exp(-1.0f / (44100.0f * .1f));
    void pop() { head_ = (head_ + 1) % capacity; --size_; }
};
