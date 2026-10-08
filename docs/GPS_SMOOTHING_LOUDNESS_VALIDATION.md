# GPS fusion and loudness — 2026-10-07

The one-second interpolation build removed GPS steps but felt slow in driving.
The replacement estimates speed and accelerometer bias together, integrating
mount/gravity-corrected acceleration between GPS readings. GPS provides drift
correction, with a short integral history for measurement delivery delays.
Corrections blend into presented speed with a 250 ms time constant; IMU motion
has no deliberate one-second delay. Existing input low-pass filtering remains.
RPM stays prescribed from speed/gear, while corrected acceleration controls load
and shift demand. The native transmission test checks that acceleration changes
load immediately without changing RPM at a fixed speed and gear.

This is an approximate delayed-observation Kalman filter with conservative
process/delay uncertainty, not a full orientation/navigation filter. It reuses
existing phone mount and gravity mapping. Incorrect mounting and phone handling
can still produce errors; physical driving validation is needed.

## Validation

- 14 Kotlin tests pass, including immediate acceleration/braking, 300 ms delayed
  GPS at 1 Hz, bias convergence, confidence weighting, correction continuity,
  sensor expiration, bounded GPS outages/recovery, standstill, launch, braking to
  zero, invalid/outlier fixes, reset and callback-rate independence.
- Emulator profile test `gps_smoothing_test.dart`: 91 ramp intervals outside
  shifts; zero flat intervals, zero wrong-direction changes, maximum successive
  RPM step 7.793. Maximum error against current speed was 0.01344 m/s, with GPS
  delivered 300 ms late and matching IMU acceleration. Zero post-settling audio
  underruns in this run; this is not a physical-device dropout guarantee.
  Results: `build/fusion-results.json`.
- Native transmission tests pass, including load/RPM independence.

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
