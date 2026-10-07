# Native port notes

Source: https://github.com/ange-yaghi/engine-sim
Revision: `85f7c3b959a908ed5232ede4f1a4ac7eafe6b630`

Constraint solver: https://github.com/ange-yaghi/simple-2d-constraint-solver
Revision: `e009f4ff1c9c4c5874e865e893cdb62e208fb2b3`

Both upstream licenses are MIT and are preserved in the vendor tree and bundled
notices. This uses the original open-source repository, not Community Edition.
The app's generic engine definition is locally authored. Exhaust impulse
responses and selectable definitions are bundled from upstream; see
[engine library notes](ENGINE_LIBRARY.md) for the scripting compiler port.

## Modifications to the vendored core

- Removed the unused desktop `delta.h` include from `synthesizer.cpp`.
- Added standard headers and a Clang `__forceinline` compatibility definition in
  `native/portable.h` (force-included by CMake / the CocoaPods target).
- Made header constants C++17 inline constants to avoid multiple definitions.
- Supplied a constructor for `GasSystem::Mix`, avoiding Clang's rejection of the
  nested aggregate's default member initializers in default arguments.
- Fixed `RingBuffer::overwrite` referring to `start` rather than `m_start`.
- Included `matrix.h` before using the complete Matrix type in sparse templates.
- Removed a duplicate Windows-backslash include in `connecting_rod.cpp`.
- Normalized `engine.cpp`'s include separator for Linux CI and macOS.
- Replaced a stale destructor assertion referring to a nonexistent member.
- Freed synthesizer transfer buffers, jitter history, connecting-rod journals,
  crankshaft-link constraints and dyno samples during teardown.
- Initialized the synthesizer latency field.
- Removed an unused fixed eight-cylinder valve-lift scratch array that overflowed
  when running V10/V12 and nine-cylinder radial definitions.
- Removed upstream frame-latency feedback: the new worker processes deterministic
  10 ms simulation frames at each definition's frequency and paces from its output queue instead.

Drive mode prescribes crank phase and angular velocity at every physics step.
The drivetrain computes RPM from speed, selected gear, final drive and tire
circumference, with bounded launch slip and a 6,000 RPM/s transition limit.
Throttle controls combustion/load sound without controlling crank speed. The
prescription is disabled during startup, shutdown and manual neutral revving.
This intentionally supplies/removes mechanical energy as a virtual drivetrain;
it is a sound simulation, not a torque or fuel-consumption measurement.

The remaining physics and sound generation algorithms remain upstream. The
upstream synthesis thread is deliberately not launched: the same worker executes
physics and synthesis serially. It transfers only final PCM into a separate
atomic SPSC buffer, so the platform audio callback never touches upstream locks.

## Limitations

Prescribed Drive motion uses direct slider-crank placement instead of solving
mechanical torque constraints. Combustion, fluid simulation and audio remain
active. Master-rod engines and free-RPM operation retain the full solver.
See [audio stability validation](AUDIO_STABILITY_VALIDATION.md) for measurements.

RevEV keeps synthesizer output as normalized floating-point PCM through the
listening mix; the legacy 16-bit API remains for upstream callers. This prevents
irreversible hard clipping before volume control. A worker-side sample-peak
limiter follows the mix, with 220 samples (~5 ms) lookahead, a 0.89 ceiling
(about -1 dBFS), and 100 ms exponential gain recovery. Fade and user volume
follow the limiter. It uses fixed storage and adds no callback locks/allocations.
This is not an oversampled true-peak limiter and cannot fix source distortion,
buffer underruns, or clipping in downstream car amplifiers.

44.1 kHz mono output; a roughly 30–40 ms producer queue plus platform/car latency.
Eight gas-flow substeps per physics step. No real-time performance guarantee
has been established for a physical handset. Production work should profile and
possibly support the output device's preferred sample rate.

The iOS adapter is source-only validation on Windows. Build and runtime verification
must occur on macOS/iOS before claiming iOS support is tested.

Generated Flutter plugin demonstration files remain in the repository. They are
not the app entry point and the generated Swift adapter is excluded by the actual
podspec, which selects `ios/Classes/`. Their cleanup was blocked by automatic
approval review; no user files were removed.
