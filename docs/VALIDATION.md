# Prototype validation â€” 2026-09-27

## Audio headroom and limiter — 2026-09-30

- Synthesizer float transport test passes on Android x86_64: values above full
  scale reach the mixer unchanged, short reads zero-fill, and legacy int16
  callers still receive saturated PCM.
- Output limiter tests pass on Android x86_64: exact low-level passthrough after
  220-sample delay, bounded overload/impulses in all listening modes, recovery,
  non-finite input handling and silence. DSP test is also added to GitHub CI.
- Native library and harness build passes. GM LS runtime: idle 717 rpm, peak
  6824 rpm, finite/bounded nonzero audio; shutdown 6154 to 3 rpm completes.
- Emulator still reports underruns (~18.6 ms processing for a 10 ms block).
  Physical-device listening is required to distinguish remaining underruns or
  source distortion from the upstream integer clipping removed here.

## Car presets and 911 — 2026-09-30

- Dropdown/native allowlist now contains 18 car presets: generic, 16 upstream
  car definitions, and a custom 911 Carrera 3.2 approximation. Excludes ATV,
  motorcycle, industrial, aircraft, and the truck-specific 454 definition.
- The 911 adapts the MIT-licensed upstream EJ25 scaffolding to six opposed
  cylinders, six journals, and evenly spaced 1-6-2-4-3-5 firing. Bore/stroke are
  95 x 74.4 mm; flow, cam, inertia and exhaust parameters are estimates. This is
  not a measured or factory-validated Porsche sound model.
- Dimensional reference: https://newsroom.porsche.com/de_CH/2019/historie/porsche-klassik-911-carrera-unternehmen-auto-assistent-porsche-ceoexclusive-label-tilman-brodbeck-16210.html
- Android extracted asset directory advances to v2 so existing installations
  receive the new script after updating.
- Flutter: 14 tests passed; analyze clean. Android x86_64 native script compile
  confirms six cylinders. Runtime smoke: idle 607 rpm, peak 6543 rpm, nonzero
  finite/bounded PCM, and shutdown 6437 to 48 rpm with completion in 555 blocks.
- Emulator work was ~23 ms per 10 ms block, with underruns: functionality passes,
  but real-time smoothness and subjective sound still need physical-device testing.

## Cabin/rumble experiment â€” 2026-09-29

- Static analysis clean; 14 Flutter tests pass, including forwarding mode and
  strength to native and locking listening controls during shutdown.
- Native DSP checks pass on Android x86_64: exact Original bypass, reduced treble,
  greater low-frequency weight, finite bounded samples, smooth mode transitions,
  and decay to silence. Steady test-signal RMS ratios: Cabin 1.000 and Rumble 1.001.
  A standalone check processed 19 seconds of signals in 36.81 ms; this is not a
  physical-phone performance measurement or a full-engine benchmark.
- Android APK builds. Integration assertions pass for live mode changes, rev,
  shutdown and switching/restarting the engine (see `build/listening-integration-final.log`).
  The emulator disconnected afterward during driver result/screenshot export,
  so the overall driver command exited unsuccessfully. Screenshots from that run
  were not exported. Earlier attempts also had debugger-transport interruptions.
- Offline comparison WAVs in `build/listening-preview/` use identical generic
  engine PCM: idle, 35% throttle, ignition off. Rumble strength is 100%, output
  gain 50%; app defaults remain Original and 50% rumble strength. Clips have no
  wholly silent blocks during steady rev and no clipped samples. They bypass
  real-time playback pacing and cannot establish phone underrun performance.
- iOS remains unbuilt; subjective sound quality needs listening on the target
  speakers. Throttle is a temporary load proxy and cabin resonances are designed,
  not measured. RMS matching is bounded and not perceptual loudness matching.

## Engine library update â€” 2026-09-29

- Static analysis: no issues; 14 Flutter tests pass, including preset forwarding,
  tachometer range, coast-down state and disabled controls during shutdown.
- Android x86_64 debug APK builds with the bundled scripts and exhaust responses.
- Android integration passes: start, idle, rev, ignition-off coast-down and
  switching from generic to Harley. Captured idle 1,650 RPM and rev 5,918 RPM;
  the sampled block took 10.34 ms, with 276 underruns on the emulator.
- Every bundled definition (25 upstream plus generic) compiles and its referenced
  impulse responses decode on the Android emulator.
- All 26 definitions pass native idle/rev, finite/bounded nonzero PCM, and
  ignition-off completion checks. The two aircraft engines were rerun after
  extending closed-throttle cranking; V10/V12 tests were rerun after removing
  upstream's unused eight-cylinder scratch buffer.
- Generic coast-down from approximately 5,900 RPM completes in about three
  seconds. Heavy engines can use the eight-second safety timeout plus fade.
- Some presets exceed the 10 ms block budget on the emulator. These checks
  establish functionality, not smooth playback or subjective sound quality on
  a physical phone. The new sound still needs comparison on the user's device.
- iOS remains unbuilt on this Windows host.

Latest native logs: `build/all-preset-runtime-v4.log` and
`build/final-large-engine-runtime.log` (the latter supersedes the aircraft and
V10/V12 entries in the first). APK build logs: `build/presets-apk-build.log`.
Integration log: `build/presets-integration-retry.log`; the first attempt was
interrupted by the emulator briefly going offline before the test ran.

## Original prototype

Environment: Windows host, Flutter 3.47.5, Android API 35 x86_64 emulator
(`RevEV_Test`). No physical handset was attached. iOS has not been built.

- `flutter analyze`: no issues.
- `flutter test`: four passing tests covering controls, failure reporting,
  background shutdown, cancellation during startup, and narrow/enlarged layout.
- Android integration: real native start, idle, throttle response, stop and
  restart passed. Screenshots are captured from the Flutter-rendered app.
- Native smoke: two full simulation lifecycles passed, with bounded/nonzero PCM,
  idle around 1,650 RPM and throttle around 6,015 RPM.
- Release APK built with ARM64, ARMv7 and x86_64 native libraries. This is a
  locally debug-signed release-mode build for installation/testing.

One recorded integration run measured 1,653 RPM at idle and 6,000 RPM after
applying 35% throttle. Its last processing block took 10.63 ms for 10 ms of audio,
with 113 buffer underruns during that session. These are emulator observations,
not proof of smooth real-time playback on a phone. Audible quality, sustained
thermal/battery behavior and Bluetooth/car latency still need device testing.
The engine/exhaust parameters are an initial generic tuning preset.

Raw latest results: `build/integration_response_data.json`, `build/integration.log`,
`build/native-smoke.log`, `build/widget-test.log`, `build/analyze.log` and
`build/release-build.log`. The integration driver stores PNGs under
`build/screenshots/`; base64 transport avoids a large JSON array for each PNG.

Build tooling warns that Flutter's integration-test plugin declares NDK 28.2,
while the installed native toolchain is 28.1. Both debug and release builds
succeeded with 28.1. Align toolchain versions during the next SDK maintenance pass.

Next acceptance step: install on the Android phone, check clean starting/idling/
revving through its speaker and intended car audio route, and monitor underruns
for several minutes before adding motion/GPS control.
