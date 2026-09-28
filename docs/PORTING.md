# Native port notes

Source: https://github.com/ange-yaghi/engine-sim
Revision: `85f7c3b959a908ed5232ede4f1a4ac7eafe6b630`

Constraint solver: https://github.com/ange-yaghi/simple-2d-constraint-solver
Revision: `e009f4ff1c9c4c5874e865e893cdb62e208fb2b3`

Both upstream licenses are MIT and are preserved in the vendor tree and bundled
notices. This uses the original open-source repository, not Community Edition.
The app's generic engine definition and identity impulse are locally authored.

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
- Removed upstream frame-latency feedback: the new worker processes deterministic
  100-step simulation frames at 10 kHz and paces from its output queue instead.

The physics and sound generation algorithms otherwise remain upstream. The
upstream synthesis thread is deliberately not launched: the same worker executes
physics and synthesis serially. It transfers only final PCM into a separate
atomic SPSC buffer, so the platform audio callback never touches upstream locks.

## Limitations

44.1 kHz mono output; a roughly 30–40 ms producer queue plus platform/car latency.
Eight gas-flow substeps per 10 kHz physics step. No real-time performance guarantee
has been established for a physical handset. Production work should profile and
possibly support the output device's preferred sample rate.

The iOS adapter is source-only validation on Windows. Build and runtime verification
must occur on macOS/iOS before claiming iOS support is tested.

Generated Flutter plugin demonstration files remain in the repository. They are
not the app entry point and the generated Swift adapter is excluded by the actual
podspec, which selects `ios/Classes/`. Their cleanup was blocked by automatic
approval review; no user files were removed.
