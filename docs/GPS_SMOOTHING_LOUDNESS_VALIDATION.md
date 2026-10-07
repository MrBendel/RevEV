# GPS smoothing and loudness — 2026-10-07

The estimator previously integrated IMU acceleration but replaced speed on each
GPS observation. A fresh yet near-zero IMU reading suppressed the GPS derivative,
so 1 Hz observations produced steps even during a smooth real-world ramp.

Live motion now advances every 20 ms. GPS slope supplies sustained prediction,
transient IMU acceleration supplies immediate changes, and new speed corrections
converge with a 0.4-second time constant. This avoids buffering a whole GPS interval;
it cannot know an unobserved maneuver or eliminate GPS measurement noise.

## Validation

- Kotlin estimator tests pass for 1 Hz acceleration/braking with zero IMU,
  delayed/jittered fixes without IMU, stale/out-of-order fixes, five-second outage
  limits, smooth recovery, and stationary bias/launch behavior.
- Emulator profile test `gps_smoothing_test.dart`: 90 ramp intervals outside
  gear shifts; zero flat intervals, zero opposite-direction changes, maximum
  successive RPM step 10.162. The sampled loop ran approximately every 65–75 ms.
  Four underruns occurred after settling in this run; it is not a zero-dropout
  guarantee. Results: `build/gps-smoothing-results.json`.
- Existing city, brisk, GPS dropout, steady cruise and motion ripple emulator
  suites pass. Launch/braking runs return to 900 RPM at rest.
- Flutter analysis and 51 tests pass. Native compressor tests verify quiet-signal
  gain, bounded loud-signal boost, silence, restart and peak limiting.

## Loudness measurements

RMS compressor: -12 dBFS threshold, 3:1, 6 dB knee, up to 6 dB makeup gain.
The existing 0.89 sample-peak ceiling, user volume, and focus gain remain intact.
No automatic volume slider increase is included (the app still starts at 15%).

The native benchmark uses actual Porsche combustion, impulse responses and the
Original listening mix, comparing output before/after the new compressor with
the same limiter. Final one-second windows of three-second runs:

| Condition | Before RMS | After RMS | Gain | Peak |
| --- | --- | --- | --- | --- |
| 900 RPM, 5% throttle | 0.0917 | 0.1829 | 6.00 dB | 0.5076 |
| 2200 RPM, 15% throttle | 0.4527 | 0.5335 | 1.43 dB | 0.8900 |

Build/run `revev_compressor_test`. For engine measurements, run
`revev_audio_bench ASSET_ROOT 300 900 0.05` or substitute `2200 0.15`.
The benchmark includes both comparison limiter paths in its DSP timing;
observed total work remained below 10 ms per 10 ms generated audio block.

These are emulator/numerical checks, not perceptual loudness or physical car
listening measurements. The compressor primarily helps quieter passages; it
does not promise a large increase when output is already near the peak ceiling.
