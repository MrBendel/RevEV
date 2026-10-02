#include "transmission_model.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdlib>

void require(bool ok, const char *msg) {
    if (!ok) {
        std::fprintf(stderr, "FAIL: %s\n", msg);
        std::exit(1);
    }
}

int main() {
    TransmissionModel tx;

    // 1. Manual / Neutral mode: gear is 0, throttle passes through, RPM is unaffected
    tx.update(0.01f, 0.0f, 0.0f, 0.5f, 0.45f, 0);
    require(tx.gear() == 0, "Manual mode must report Neutral/0");
    require(tx.simulatedThrottle() == 0.45f, "Manual throttle altered");

    // 2. 5-speed Carrera 3.2 configuration
    const double carreraRatios[] = {3.50, 2.06, 1.41, 1.07, 0.86};
    tx.configure(5, carreraRatios, 3.44, 8000.0, 900.0, 0.31);

    // At 0 km/h, stopped in Drive: gear is 1, target RPM is at idle (900 RPM)
    for (int i = 0; i < 50; ++i) {
        tx.update(0.01f, 0.0f, 0.0f, 0.5f, 0.0f, 1);
    }
    require(tx.gear() == 1, "Stopped car must be in 1st gear");
    require(std::abs(tx.targetRpm() - 900.0f) < 5.0f, "Idle RPM not 900 at standstill");

    // 3. Hard acceleration pull (flooring it: 2.8 m/s^2, 1.0 aggressiveness):
    // Should wind up 1st gear all the way near redline before shifting
    float speed = 0.0f;
    int maxGearSeen = 1;
    bool sawUpshift = false;
    float peakRpmIn1st = 0.0f;

    for (int step = 0; step < 400; ++step) { // 4 seconds of hard acceleration
        speed += 2.8f * 0.01f; // m/s
        tx.update(0.01f, speed, 2.8f, 1.0f, 0.0f, 1);
        if (tx.gear() == 1) {
            peakRpmIn1st = std::max(peakRpmIn1st, tx.targetRpm());
        }
        if (tx.gear() > 1) {
            sawUpshift = true;
        }
        maxGearSeen = std::max(maxGearSeen, tx.gear());
    }
    std::printf("Hard pull peak RPM in 1st: %.1f, max gear: %d\n", peakRpmIn1st, maxGearSeen);
    require(peakRpmIn1st > 6800.0f, "Aggressive shift did not reach near redline");
    require(sawUpshift, "Did not upshift under hard acceleration");
    require(maxGearSeen >= 2, "Failed to reach higher gear");

    // 4. Cruising at 100 km/h (27.78 m/s, accel = 0):
    // Should upshift to top gear (5th gear) for quiet, low-RPM cruising without drone
    tx.reset();
    speed = 27.78f;
    for (int step = 0; step < 500; ++step) {
        tx.update(0.01f, speed, 0.0f, 0.3f, 0.0f, 1);
    }
    std::printf("100 km/h cruise gear: %d, RPM: %.1f\n", tx.gear(), tx.targetRpm());
    require(tx.gear() == 5, "Cruise did not upshift to 5th gear");
    require(tx.targetRpm() < 3000.0f, "Cruising RPM too high, causing drone");
    require(tx.targetRpm() > 1800.0f, "Cruising RPM unrealistically low");

    // 5. Deceleration to a stop:
    // When slowing down from 100 km/h to 0 km/h, downshifts sequentially to 1st gear and idles
    for (int step = 0; step < 600; ++step) {
        speed = std::max(0.0f, speed - 1.8f * 0.01f);
        tx.update(0.01f, speed, -1.8f, 0.5f, 0.0f, 1);
    }
    std::printf("After braking to stop: speed %.1f, gear: %d, RPM: %.1f\n", speed, tx.gear(), tx.targetRpm());
    require(tx.gear() == 1, "Braking did not downshift back to 1st gear");
    require(std::abs(tx.targetRpm() - 900.0f) < 5.0f, "RPM did not return to idle after stopping");

    // 6. Test 4-speed Turbo 3.3 configuration
    const double turboRatios[] = {3.15, 1.79, 1.21, 0.89};
    tx.configure(4, turboRatios, 3.44, 8000.0, 900.0, 0.31);
    require(tx.gearCount() == 4, "Turbo must have 4 gears");

    // Cruise at 120 km/h in Turbo 3.3 should be 4th gear
    for (int step = 0; step < 300; ++step) {
        tx.update(0.01f, 33.33f, 0.0f, 0.5f, 0.0f, 1);
    }
    require(tx.gear() == 4, "Turbo did not cruise in 4th gear");

    // 7. Test 7-speed Ferrari F136 configuration
    const double ferrariRatios[] = {3.08, 2.19, 1.63, 1.29, 1.03, 0.84, 0.68};
    tx.configure(7, ferrariRatios, 4.50, 12000.0, 1000.0, 0.31);
    require(tx.gearCount() == 7, "Ferrari must have 7 gears");

    // 8. Non-finite safety
    tx.update(0.01f, NAN, INFINITY, NAN, 0.0f, 1);
    require(std::isfinite(tx.targetRpm()), "Non-finite RPM output");
    require(std::isfinite(tx.simulatedThrottle()), "Non-finite throttle output");

    std::printf("All TransmissionModel tests passed successfully!\n");
    return 0;
}
