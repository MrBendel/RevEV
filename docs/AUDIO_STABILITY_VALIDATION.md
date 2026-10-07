# Audio stability validation — 2026-10-06

Drive previously spent about 22 ms simulating each 10 ms audio block on the
Android x86_64 emulator. Direct prescribed slider-crank motion reduces this to
about 6.2 ms including DSP, retaining combustion, eight fluid substeps, 20 kHz
simulation, and full impulse responses. The 10-second benchmark retained nearly
identical PCM energy. Manual neutral, startup/shutdown, and articulated rods
retain the full mechanical solver; their throughput is not fixed by this change.

The profile-mode `integration_test/audio_stability_test.dart` ran the native
AAudio stream for three sessions after an eight-second warmup each:

| Session | Measured duration | Median work | P95 work | New underruns |
| --- | --- | --- | --- | --- |
| 1 | 120.455 s | 5.884 ms | 8.094 ms | 0 |
| 2 | 30.504 s | 6.103 ms | 7.897 ms | 0 |
| 3 | 30.482 s | 6.277 ms | 8.021 ms | 0 |

A separate Android focus fixture requested eight alternating transient and
duckable interruptions during session 1; Android granted all eight. Temporary
loss muted output without stopping the session, and focus gain restored output.
The harness checked session continuity, RPM spread, throughput and restart.
Android may perform ducking itself without notifying the app.

Native continuity tests cover starvation across callback boundaries and fading
back into fresh PCM. Prescribed-motion tests check RPM, crank phase, positive
cylinder volume, full piston travel, wrist-pin alignment, finite audio and
release back to free physics. Kotlin tests cover repeated focus cycles, stale
callbacks and permanent loss. Flutter tests cover transient inactive versus
background lifecycle handling.

Reproduce the soak using `flutter drive --profile
--driver=test_driver/integration_test.dart
--target=integration_test/audio_stability_test.dart
--dart-define=EXPECT_AUDIO_FOCUS_INTERRUPTION=true -d emulator-5554`.
Start the fixture when `AUDIO_SOAK_READY` appears; see its README. Driver metrics
are written to `build/integration_response_data.json`.

These are emulator measurements, not a physical handset/car listening test.
They do not establish Bluetooth route recovery or long-duration thermal behavior.
