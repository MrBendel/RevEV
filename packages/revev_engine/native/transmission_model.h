#pragma once
#include <algorithm>
#include <cmath>
#include <vector>

// TransmissionModel: Simulates an automatic transmission and drivetrain for RevEV.
// Translates vehicle speed (GPS) and acceleration (phone accelerometer) into realistic
// gear selections, engine RPM, shift cuts, rev-match blips, and load-proportional throttle.
class TransmissionModel {
public:
    TransmissionModel() {
        reset();
    }

    void reset() {
        gear_ = 1;
        targetRpm_ = idleRpm_;
        simulatedThrottle_ = 0.0f;
        shiftTimer_ = 0.0f;
        isShifting_ = false;
        shiftDirection_ = 0;
        clutchEngaged_ = 0.0f;
        prevSpeed_ = 0.0f;
        shiftAccel_ = 0.0f;
        kickdownDemandTime_ = 0.0f;
        shiftCooldown_ = 0.0f;
    }

    void configure(int gearCount, const double *ratios, double finalDrive, double redline, double idle = 900.0, double tireRadius = 0.31) {
        gearCount_ = std::clamp(gearCount, 1, 10);
        ratios_.clear();
        for (int i = 0; i < gearCount_; ++i) {
            ratios_.push_back(static_cast<float>(ratios[i]));
        }
        finalDrive_ = static_cast<float>(finalDrive);
        redlineRpm_ = static_cast<float>(redline);
        idleRpm_ = static_cast<float>(idle);
        tireRadius_ = static_cast<float>(tireRadius);
        reset();
    }

    // driveMode: 0 = Manual / Neutral, 1 = GPS Drive, 2 = Simulated Drive
    // speedMps: vehicle speed from GPS (m/s)
    // accelMps2: forward acceleration (m/s^2)
    // aggressiveness: 0.0 (eco, low shift RPM) to 1.0 (race, holds to redline)
    // manualThrottle: throttle when in manual mode
    void update(float dt, float speedMps, float accelMps2, float aggressiveness, float manualThrottle, int driveMode) {
        if (!std::isfinite(speedMps) || speedMps < 0.0f) speedMps = 0.0f;
        if (!std::isfinite(accelMps2)) accelMps2 = 0.0f;
        if (!std::isfinite(aggressiveness)) aggressiveness = 0.5f;
        aggressiveness = std::clamp(aggressiveness, 0.0f, 1.0f);

        if (driveMode == 0) {
            // Manual mode: neutral revving
            gear_ = 0; // Neutral
            isShifting_ = false;
            shiftTimer_ = 0.0f;
            simulatedThrottle_ = manualThrottle;
            shiftAccel_ = kickdownDemandTime_ = shiftCooldown_ = 0.0f;
            return;
        }

        // A manual-to-drive transition must never index ratios_[-1].
        if (gear_ < 1) gear_ = 1;
        dt = std::isfinite(dt) ? std::clamp(dt, 0.0001f, 0.1f) : 0.01f;
        shiftAccel_ += (accelMps2 - shiftAccel_) * dt / (0.35f + dt);
        shiftCooldown_ = std::max(0.0f, shiftCooldown_ - dt);

        const float speedKmh = speedMps * 3.6f;

        // Accelerometer-based driver demand:
        // normAccel: 0 at cruise, 1.0 at >= 2.8 m/s^2 (~0.3g)
        const float normAccel = std::clamp(shiftAccel_ / 2.8f, 0.0f, 1.0f);

        // Effective shifting aggressiveness:
        // Combines user preference (aggressiveness) with actual acceleration demand
        const float effectiveAggression = std::clamp(
            aggressiveness * 0.35f + normAccel * (0.65f + 0.35f * aggressiveness),
            0.0f, 1.0f
        );
        // Reject alternating mount/pedaling pulses. Real acceleration must
        // persist before demanding a lower gear, and shifts need time to settle.
        kickdownDemandTime_ = normAccel > 0.65f && effectiveAggression > 0.60f
            ? std::min(kickdownDemandTime_ + dt, 1.0f) : 0.0f;

        // Calculate shift threshold RPM based on redline and aggressiveness
        const float minShiftRpm = std::max(idleRpm_ * 2.2f, redlineRpm_ * 0.36f);
        const float maxShiftRpm = redlineRpm_ * 0.94f;
        const float shiftUpRpm = minShiftRpm + (maxShiftRpm - minShiftRpm) * effectiveAggression;

        // Downshift RPM threshold
        const float shiftDownRpm = std::max(idleRpm_ * 1.30f, minShiftRpm * 0.52f);

        // Handle active shifting timer
        if (shiftTimer_ > 0.0f) {
            shiftTimer_ -= dt;
            if (shiftTimer_ <= 0.0f) {
                shiftTimer_ = 0.0f;
                isShifting_ = false;
                shiftDirection_ = 0;
            }
        }

        // Automatic gear shift logic (when not mid-shift)
        if (!isShifting_ && shiftCooldown_ <= 0.0f && speedKmh > 1.0f) {
            const float currentRatio = ratios_[gear_ - 1];
            const float currentGearRpm = calcDrivetrainRpm(speedKmh, currentRatio);

            // 1. Upshift check (under load or steady cruising)
            bool shouldUpshift = false;
            if (gear_ < gearCount_) {
                const float nextRatio = ratios_[gear_];
                const float nextGearRpm = calcDrivetrainRpm(speedKmh, nextRatio);
                const float gearLugFloor = std::max(idleRpm_ * 1.5f, 1350.0f + (gear_ - 1) * 150.0f);
                const float cruiseShiftUpRpm = minShiftRpm + 600.0f * effectiveAggression;
                const bool cruiseUpshift = (normAccel < 0.20f && accelMps2 >= -0.2f &&
                                            currentGearRpm >= cruiseShiftUpRpm &&
                                            nextGearRpm >= gearLugFloor);
                if ((currentGearRpm >= shiftUpRpm && nextGearRpm >= gearLugFloor) || cruiseUpshift) {
                    shouldUpshift = true;
                }
            }

            if (shouldUpshift) {
                gear_++;
                isShifting_ = true;
                shiftDirection_ = 1;
                shiftTimer_ = 0.18f; // 180 ms torque cut
                shiftCooldown_ = 0.8f;
            }
            // 2. Downshift check (Deceleration or Kickdown)
            else if (gear_ > 1) {
                const float prevRatio = ratios_[gear_ - 2];
                const float prevGearRpm = calcDrivetrainRpm(speedKmh, prevRatio);

                // Kickdown if aggressive acceleration and lower gear won't over-rev
                const bool kickdownCondition = (kickdownDemandTime_ >= 0.35f &&
                                                prevGearRpm < redlineRpm_ * 0.82f);
                // Deceleration downshift to prevent lugging/stalling
                const bool decelCondition = (currentGearRpm < shiftDownRpm && prevGearRpm < redlineRpm_ * 0.85f);

                if (kickdownCondition || decelCondition) {
                    gear_--;
                    isShifting_ = true;
                    shiftDirection_ = -1;
                    shiftTimer_ = 0.16f; // 160 ms rev-match blip
                    shiftCooldown_ = 0.8f;
                }
            }
        }

        // Stopped / Launch clutch slip
        if (speedKmh < 1.0f) {
            gear_ = 1;
            clutchEngaged_ = 0.0f;
        } else if (speedKmh < 12.0f) {
            clutchEngaged_ = std::clamp((speedKmh - 1.0f) / 11.0f, 0.0f, 1.0f);
        } else {
            clutchEngaged_ = 1.0f;
        }

        // Calculate drivetrain RPM in current gear
        const float activeRatio = (gear_ >= 1 && gear_ <= gearCount_) ? ratios_[gear_ - 1] : ratios_[0];
        const float drivetrainRpm = calcDrivetrainRpm(speedKmh, activeRatio);

        // Blend clutch slip at launch: at 0 km/h, idle; as car accelerates, locks to drivetrain RPM
        // A stationary phone's acceleration must not rev a stopped engine.
        // Screen throttle changes load in Drive; neutral is the free-rev mode.
        // Shift demand has deliberate hysteresis; launch slip must instead
        // follow the current filtered IMU input, especially when braking or
        // relaunching in short traffic gaps.
        const float launchDemand = std::clamp(accelMps2 / 2.8f, 0.0f, 1.0f);
        const float launchRpm = idleRpm_ + (speedKmh >= 1.0f ? launchDemand : 0.0f) * 1500.0f;
        float baseRpm = clutchEngaged_ * drivetrainRpm + (1.0f - clutchEngaged_) * launchRpm;
        baseRpm = std::clamp(baseRpm, idleRpm_, redlineRpm_ * 0.98f);

        // Throttle synthesis:
        // Acceleration -> throttle load.
        // Braking / coasting -> off-throttle overrun.
        // Shifting -> cut or blip.
        if (isShifting_) {
            if (shiftDirection_ > 0) {
                // Upshift cut: throttle drops to 0.04 to relieve torque and sneeze turbo BOV
                simulatedThrottle_ = 0.04f;
            } else {
                // Downshift blip: throttle blips to 0.55 for rev-match roar
                simulatedThrottle_ = 0.55f;
            }
        } else {
            const float rpmFrac = std::clamp((baseRpm - idleRpm_) / (redlineRpm_ - idleRpm_), 0.0f, 1.0f);
            const float cruiseThrottle = 0.12f + 0.28f * rpmFrac;

            if (driveMode == 2) {
                // Simulated Drive (Speed Sim):
                // Direct response to user's manual throttle slider when set.
                if (manualThrottle > 0.01f) {
                    simulatedThrottle_ = std::clamp(manualThrottle, 0.0f, 1.0f);
                } else if (speedKmh > 1.0f) {
                    // Cruising when speed slider is active without manual throttle
                    simulatedThrottle_ = cruiseThrottle;
                } else {
                    simulatedThrottle_ = 0.0f;
                }
            } else {
                // GPS Drive:
                if (speedKmh < 1.0f) {
                    // Standstill / Stoplight: zero throttle (idle) unless user manually presses throttle on screen
                    simulatedThrottle_ = (manualThrottle > 0.01f) ? std::clamp(manualThrottle, 0.0f, 1.0f) : 0.0f;
                } else if (accelMps2 > 0.05f) {
                    // Positive acceleration: throttle proportional to demand
                    simulatedThrottle_ = std::clamp(cruiseThrottle + normAccel * (1.0f - cruiseThrottle), 0.0f, 1.0f);
                } else if (accelMps2 < -0.15f) {
                    // Deceleration / braking: closed throttle / overrun pops
                    simulatedThrottle_ = 0.02f;
                } else {
                    // Cruising / steady speed: light maintenance throttle
                    simulatedThrottle_ = cruiseThrottle;
                }
                if (speedKmh >= 1.0f && manualThrottle > 0.01f) {
                    simulatedThrottle_ = std::max(simulatedThrottle_, manualThrottle);
                }
            }
        }

        targetRpm_ = baseRpm;
        prevSpeed_ = speedKmh;
    }

    inline float calcDrivetrainRpm(float speedKmh, float gearRatio) const {
        constexpr float pi = 3.14159265f;
        const float wheelCircumference = 2.0f * pi * tireRadius_;
        const float wheelRps = (speedKmh / 3.6f) / wheelCircumference;
        return wheelRps * 60.0f * gearRatio * finalDrive_;
    }

    int gear() const { return gear_; }
    float targetRpm() const { return targetRpm_; }
    float simulatedThrottle() const { return simulatedThrottle_; }
    bool isShifting() const { return isShifting_; }
    int gearCount() const { return gearCount_; }
    float redlineRpm() const { return redlineRpm_; }

private:
    int gear_ = 1;
    int gearCount_ = 5;
    std::vector<float> ratios_{3.50f, 2.06f, 1.41f, 1.07f, 0.86f};
    float finalDrive_ = 3.44f;
    float redlineRpm_ = 8000.0f;
    float idleRpm_ = 900.0f;
    float tireRadius_ = 0.31f;

    float targetRpm_ = 900.0f;
    float simulatedThrottle_ = 0.0f;
    float shiftTimer_ = 0.0f;
    bool isShifting_ = false;
    int shiftDirection_ = 0;
    float clutchEngaged_ = 0.0f;
    float prevSpeed_ = 0.0f;
    float shiftAccel_ = 0.0f;
    float kickdownDemandTime_ = 0.0f;
    float shiftCooldown_ = 0.0f;
};
