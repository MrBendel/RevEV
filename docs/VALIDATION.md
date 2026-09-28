# Prototype validation — 2026-09-27

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
