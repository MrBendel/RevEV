#include "engine_runtime.h"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <thread>
#include <array>

int main() {
    EngineRuntime runtime;
    for (int pass = 0; pass < 2; ++pass) {
        runtime.setThrottle(0);
        runtime.start();
        double energy = 0;
        float idle = 0, high = 0;
        std::array<float, 441> pcm{};
        auto next = std::chrono::steady_clock::now() + std::chrono::milliseconds(100);
        for (int i = 0; i < 800; ++i) {
            if (i == 300) { idle = runtime.rpm(); runtime.setThrottle(0.45f); }
            std::this_thread::sleep_until(next);
            next += std::chrono::milliseconds(10);
            runtime.render(pcm.data(), pcm.size());
            for (float s : pcm) {
                if (!std::isfinite(s) || std::abs(s) > 1) return 2;
                energy += s*s;
            }
            if (i > 300) high = std::max(high, runtime.rpm());
        }
        std::printf("pass=%d idle=%.0f high=%.0f energy=%.3f block_ms=%.2f underruns=%u failed=%d\n",
            pass, idle, high, energy, runtime.workMs(), runtime.underruns(), runtime.failed());
        runtime.stop();
        if (runtime.failed() || energy < 0.01 || high < idle + 100 || idle < 500) return 1;
    }
    return 0;
}
