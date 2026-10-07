# GPS smoothing and loudness — 2026-10-07

The estimator previously integrated IMU acceleration but replaced speed on each
GPS observation. A fresh yet near-zero IMU reading suppressed the GPS derivative,
so 1 Hz observations produced steps even during a smooth real-world ramp.

Live motion now advances every 20 ms through a one-second linear segment toward
each newly received GPS speed. Regular 1 Hz fixes therefore play one second late,
plus their original delivery age. Early/late updates retarget from the current
output, never jumping it. No future-speed extrapolation is used after acquisition.
An outage finishes the last segment then holds; recovery takes another second.
Shift/load acceleration uses the delayed segment slope rather than current IMU
demand. Sensor noise cannot modulate stationary or steady buffered speed.

## Validation

- Kotlin estimator tests pass for 1 Hz acceleration/braking with zero IMU,
  delayed/jittered fixes without IMU, stale/out-of-order fixes, outage holds,
  exact one-second latency, callback-rate independence, smooth recovery and
  stationary noise. Before first acquisition only, IMU integration is bounded.
- Emulator profile test `gps_smoothing_test.dart`: 89 ramp intervals outside
  gear shifts; zero flat intervals, zero opposite-direction changes, maximum
  successive RPM step 14.356. Maximum error relative to the one-second-delayed
  ramp was 0.0322 m/s. The sampled loop ran approximately every 65–75 ms.
  Ten underruns occurred after settling in this run (below the existing audio
  stability budget of two per second); it is not a zero-dropout guarantee.
  Results: `build/linear-gps-results.json`.
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
