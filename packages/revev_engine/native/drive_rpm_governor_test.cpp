#include "drive_rpm_governor.h"
#include <cstdio>
#include <cstdlib>

static void require(bool value, const char *message) {
    if (!value) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}

int main() {
    // Delayed first-order engine response with different throttle sensitivities.
    // This tests feedback behavior; the device test separately uses combustion.
    for (float gain : {7000.0f, 12000.0f, 18000.0f}) {
        DriveRpmGovernor governor;
        float rpm = 1000.0f, actuator = 0.0f;
        float low = 10000.0f, high = 0.0f;
        for (int step = 0; step < 6000; ++step) {
            const float demand = 0.18f + 0.04f * std::sin(step * .01f * 6.283185f);
            const float output = governor.update(.01f, 2500.0f, rpm, demand, false);
            require(std::isfinite(output) && output >= 0 && output <= 1, "bounded throttle");
            actuator += (output - actuator) * .01f / .15f;
            const float load = step > 3000 ? 300.0f : 0.0f;
            rpm += (1000 + gain * actuator - load - rpm) * .01f / .45f;
            if (step > 5000) { low = std::min(low, rpm); high = std::max(high, rpm); }
        }
        require(std::abs(rpm - 2500) < 100, "recover target after load change");
        require(high - low < 180, "reject periodic demand without hunting");
    }
    DriveRpmGovernor governor;
    for (int i = 0; i < 2000; ++i) governor.update(.01f, 900, 1600, .2f, false);
    require(governor.update(.01f, 4000, 1600, .3f, false) > .1f, "recover from idle saturation");
    require(governor.update(.01f, 4000, 2000, .04f, true) == .04f, "retain upshift cut");
    require(governor.update(.01f, 4000, 2000, .55f, true) == .55f, "retain downshift blip");
    governor.reset();
    DriveRpmGovernor fresh;
    require(governor.update(.01f, 2500, 1700, .18f, false) ==
        fresh.update(.01f, 2500, 1700, .18f, false), "reset removes learned trim and slope");
    require(governor.update(.01f, NAN, 1700, .18f, false) == 0, "invalid input silences demand");
    std::puts("Drive RPM governor tests passed");
}
