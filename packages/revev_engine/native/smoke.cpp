#include "engine_runtime.h"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <thread>
#include <array>

int main(int argc, char **argv) {
    EngineRuntime runtime;
    for (int pass = 0; pass < (argc > 2 ? 1 : 2); ++pass) {
        runtime.setThrottle(0);
        runtime.start(argc > 1 ? argv[1] : "", argc > 2 ? argv[2] : "porsche/911_carrera_32");
        double energy = 0;
        float idle = 0, high = 0;
        std::array<float, 441> pcm{};
        auto next = std::chrono::steady_clock::now() + std::chrono::milliseconds(100);
        // Aircraft flywheels can take 12 simulated seconds to crank.
        const std::string id = argc > 2 ? argv[2] : "porsche/911_carrera_32";
        const int idleBlocks = id == "atg-video-2/09_radial_9" || id == "atg-video-2/11_merlin_v12" ? 2400 : 800;
        for (int i = 0; i < idleBlocks + 600; ++i) {
            if (i == idleBlocks) { idle = runtime.rpm(); runtime.setThrottle(0.45f); }
            std::this_thread::sleep_until(next);
            next += std::chrono::milliseconds(10);
            runtime.render(pcm.data(), pcm.size());
            for (float s : pcm) {
                if (!std::isfinite(s) || std::abs(s) > 1) return 2;
                energy += s*s;
            }
            if (i > idleBlocks) high = std::max(high, runtime.rpm());
        }
        std::printf("pass=%d idle=%.0f high=%.0f energy=%.3f block_ms=%.2f underruns=%u failed=%d\n",
            pass, idle, high, energy, runtime.workMs(), runtime.underruns(), runtime.failed());
        const float beforeStop = runtime.rpm();
        runtime.shutdown();
        int rundownBlocks = 0;
        while (!runtime.finished() && !runtime.failed() && rundownBlocks < 1200) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            runtime.render(pcm.data(), pcm.size());
            for (float s : pcm) if (!std::isfinite(s) || std::abs(s) > 1) return 4;
            ++rundownBlocks;
        }
        std::printf("shutdown from=%.0f to=%.0f blocks=%d finished=%d\n", beforeStop, runtime.rpm(), rundownBlocks, runtime.finished());
        const bool finished = runtime.finished();
        runtime.stop();
        if (!finished || rundownBlocks < 1) return 5;
        if (runtime.failed() || energy < 0.01 || high < idle + 100 || idle < 500) return 1;
    }
    return 0;
}
