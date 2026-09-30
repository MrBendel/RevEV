#include "listening_mix.h"
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>

void require(bool condition, const char *message) {
    if (!condition) { std::fprintf(stderr, "%s\n", message); std::exit(1); }
}
int main() {
    constexpr double tau = 6.283185307179586;
    std::array<double, 3> energy{}, bass{}, treble{};
    const auto start = std::chrono::steady_clock::now();
    for (int mode = 0; mode < 3; ++mode) {
        ListeningMix mix;
        float last = 0;
        for (int i = 0; i < 44100*4; ++i) {
            const double t = i/44100.0;
            const float x = .12*std::sin(tau*65*t) + .12*std::sin(tau*300*t) + .08*std::sin(tau*3000*t);
            const float y = mix.process(x, mode, 1, 1);
            require(std::isfinite(y) && std::abs(y) <= 1, "invalid output");
            if (mode == 0) require(y == x, "Original changed the signal");
            require(std::abs(y-last) < .2, "discontinuous signal"); last = y;
            if (i >= 44100*3) {
                energy[mode] += y*y;
                bass[mode] += y*std::sin(tau*65*t);
                treble[mode] += y*std::sin(tau*3000*t);
            }
        }
        float tail = 0;
        for (int i = 0; i < 44100; ++i) tail = mix.process(0, mode, 1, 0);
        require(std::abs(tail) < 1e-6, "rumble persists without excitation");
    }
    require(std::abs(treble[1]) < std::abs(treble[0])*.3, "cabin does not reduce treble");
    require(std::abs(bass[2]) > std::abs(bass[1])*1.1, "rumble does not add low-end weight");
    for (int m = 1; m < 3; ++m) {
        const double ratio = std::sqrt(energy[m]/energy[0]);
        std::printf("mode=%d RMS ratio=%.3f bass=%.3f treble=%.3f\n", m, ratio, bass[m], treble[m]);
        require(ratio > .8 && ratio < 1.2, "level matching drifted");
    }
    ListeningMix switched;
    float last = 0;
    for (int i = 0; i < 44100*3; ++i) {
        const int mode = (i / 4410) % 3;
        const float y = switched.process(.2f, mode, i%2, i%2);
        require(std::isfinite(y) && std::abs(y) <= 1, "switch invalid");
        if (i) require(std::abs(y-last) < .01, "mode switch clicked");
        last = y;
    }
    ListeningMix peaks;
    for (int i = 0; i < 44100; ++i) {
        const float y = peaks.process(i%2 ? .999f : -.999f, 2, 1, 1);
        require(std::isfinite(y) && std::abs(y) <= 1, "peak protection failed");
    }
    const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now()-start).count();
    std::printf("DSP checks passed; %.2f ms total for 19 seconds of audio\n", ms);
}
