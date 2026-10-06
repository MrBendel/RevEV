# Deterministic drive RPM validation

Validated on Android emulator `emulator-5554`, profile build, 2026-10-06.
Preset: `porsche/911_carrera_32`. Synthetic inputs enter after mount-axis mapping.

| Harness scenario | Result | Observed behavior |
| --- | --- | --- |
| Steady cruise, 15 mph | Passed | Settled RPM P95-P5 = 0; mean absolute target error = 0 RPM |
| Acceleration ripple, 15 mph | Passed | Settled RPM P95-P5 = 52.94; mean target error = 0.29 RPM; small fused-speed variation remains |
| City launch, 0-30 mph | Passed | Peak 4,622 RPM; gears 1-3; braking RPM falls after shift transitions |
| Brisk launch, 0-60 mph | Passed | Peak 5,966 RPM; gears 1-5; braking RPM falls after shift transitions |
| GPS dropout | Passed | IMU extrapolation and stale-speed hold exercised; recovered and returned to idle |

All five runs ended at exactly 900 RPM. The city and brisk braking samples more
than 0.6 seconds after a gear change had zero target error and no RPM increases.
The dropout trace had transient braking differences up to 124.35 RPM in that
same selection. Runtime target and actual RPM are read asynchronously, and the
bounded trajectory intentionally permits temporary error during target changes.

Native tests directly exercised combustion/audio at prescribed 900, 1700, 2200
and 3000 RPM while switching throttle between 0 and 80 percent. Generic, Porsche
and GM LS presets retained commanded RPM and crank phase progression within
1e-6 RPM and 1e-9 radians; PCM remained finite and nonzero. Disabling the
prescription restored free engine rundown. Model/transmission tests also passed,
including stationary acceleration noise, shift bounds and replay under different
manual throttle values. Flutter analysis was clean and all 51 unit/widget tests
passed.

## Remaining limitations

Audio throughput is unresolved: scenario median work times were approximately
27 ms for 10 ms of synthesized audio, with frequent underruns. These tests do not
establish glitch-free playback or physical-handset performance. The replay
harness does not test automatic mount-axis selection, actual GPS reception, or
Bluetooth/car latency. It validates the RPM path separately from those issues.

## Reproduce

```text
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/steady_drive_test.dart -d emulator-5554
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/drive_harness_test.dart -d emulator-5554
```

Build and run native targets `revev_drive_model_test`,
`revev_transmission_test`, and `revev_prescribed_rpm_test`. For bundled presets,
pass asset root and preset ID to `revev_prescribed_rpm_test`.
