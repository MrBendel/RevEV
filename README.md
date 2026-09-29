# RevEV — Flutter + engine-sim

An Android-first, cross-platform sound experiment. The app runs Ange Yaghi's
original MIT-licensed **engine-sim combustion simulation**, not a recording or a
stand-in oscillator. The interface uses original vector gauges and procedural
leather grain inspired by the supplied dashboard references; no reference photos
are shipped. Upstream exhaust impulse responses shape the simulated sound.

## Try it

Requirements: Flutter 3.47.5 / Dart 3.13.4, Java 17+, Android SDK 36, NDK
28.1.13356709, CMake 3.10.2. Android 8 (API 26) or newer is required for AAudio.
Gradle can install missing SDK build components when licenses are available.

```powershell
flutter pub get
flutter devices
flutter run --release -d <your-android-device-id>
```

On this development machine Flutter is installed at
`C:\Users\andre\tools\flutter\bin\flutter.bat`; Java is at
`C:\Users\andre\tools\Java\jdk-17.0.20+8`.

Enable USB debugging on the phone, connect it, and accept its debugging prompt.
Tap **Start**, allow the engine to crank, then gradually move the throttle.
Output starts at 15%. No microphone, location, or motion permission is requested.

```powershell
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. Release builds require the
dedicated upload signing key. Run `python scripts/setup_signing.py` first.
See [GitHub and Play publishing](docs/ANDROID_PUBLISHING.md) for signed bundles,
the GitHub build button, and internal testing releases.

## What works in this prototype

- An engine dropdown with the generic 2.0 L inline-four and 25 complete upstream
  engine definitions, including VTEC, Hayabusa, Subaru, Audi, V6/V8/V10/V12 and radials.
  Stop before switching. Templates compile on the native worker; first startup
  also unpacks the bundled library on Android.
- Starter, ignition and rev limiter. Stop cuts ignition and lets the simulated
  crankshaft coast down, followed by a short fade. A bounded timeout handles
  engines that do not settle promptly. Backgrounding still stops immediately.
- Real combustion, gas-flow and crankshaft simulation with native audio synthesis.
- Throttle and volume controls, animated RPM/throttle/output instruments.
- Performance panel: processing time per 10 ms simulated-audio block and underruns.
- Expand **Debug dashboard** below the controls for live RPM, sampled timing
  averages/peaks, recent P95, a timing chart and underruns. **Copy debug report**
  copies a JSON session summary. Results remain after Stop; Start resets them.
  Timing snapshots are polled every 150 ms, not recorded for every native block;
  the chart and P95 cover the latest 400 samples (about one minute).
- With the engine stopped, **Run 15-second test** runs 5 seconds at idle,
  5 seconds at 35% throttle, and 5 seconds back at idle, then stops. Startup
  time and final coast-down are additional. Throttle and output volume are locked during the test;
  set output first. Stop, Cancel test, backgrounding or an engine/diagnostics
  failure cancels the sequence. The JSON report includes the result and actual
  phase start times, throttle targets and volume. Timing is scheduled in the
  foreground UI; it is not a precise native benchmark.
- Audio-focus loss / app backgrounding stops playback; resuming requires Start.
- Android AAudio output; an iOS AVAudioEngine adapter shares the same core.

The first engine is a tuning/test preset, not a sonic recreation of a particular
car. Its exhaust now uses upstream's mild exhaust impulse response, with lower
noise and jitter. Bundled engines use their own scripted exhaust responses and
simulation frequencies. High-frequency or many-cylinder definitions can exceed
a device's processing budget and produce underruns; check the debug dashboard.
CPU performance on the emulator is not a phone benchmark.
The reported block time is simulation work, not CPU percentage or speaker latency.
The audio rate is fixed at 44.1 kHz; Android may need sample-rate conversion.

## Architecture

`lib/` contains the Flutter dashboard. `packages/revev_engine/` is a local plugin:

- Method channel: start with preset ID, ignition shutdown, immediate stop,
  control targets and diagnostic snapshots.
- `native/engine_preset.cpp`: explicit engine geometry and fuel/valve parameters.
- `native/engine_runtime.cpp`: a native worker advances physics in 10 ms blocks,
  renders upstream audio synchronously, and fills an SPSC queue (about 30–40 ms).
- Native callbacks consume floating-point samples without locks, allocation,
  file I/O, or Dart calls. The simulation's internal locks stay on its worker.
- Android uses JNI + AAudio; iOS uses Objective-C++ + AVAudioSourceNode.

The bundled Piranha compiler loads only allowlisted upstream scripts; no desktop
graphics engine, backend, account system, or runtime downloads are needed.
See [bundled engine library](docs/ENGINE_LIBRARY.md) for provenance and generation.
Flutter assets contain the
upstream license notices, accessible through **Open-source credits**.

## iOS

The iOS adapter and CocoaPods configuration are included but **not built or tested
on this Windows machine**. A Mac with Xcode, CocoaPods, and an iPhone is needed.
This project disables Swift Package Manager in its Flutter configuration because
the native plugin uses a local podspec. The generated SwiftPM/template plugin
files are unused; `ios/Classes/` contains the actual adapter.

```sh
flutter pub get
cd ios && pod install && cd ..
flutter run -d <iphone-device-id>
```

## Checks

```powershell
flutter analyze
flutter test
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/engine_test.dart -d <android-id>
```

Integration captures go to `build/screenshots/`. The test verifies real native
RPM response and restart, not only mocked method calls. `native/smoke.cpp` can
also be cross-compiled with the Android NDK and run through adb. It checks finite
bounded PCM, nonzero audio energy, idle, throttle response, and repeated teardown.

## Next milestones

1. Measure sustained performance, battery use and audio-route delay on a phone.
2. Tune the engine and exhaust response; compare multiple engine configurations.
3. Add motion/GPS estimation and a virtual drivetrain.
4. Implement and test background sessions and headset/car route changes.
5. Investigate Android Auto / CarPlay eligibility and native integrations.

This build is a manual foreground sound test. It has no GPS, driving mode, tire
effects, background playback, Android Auto, or CarPlay integration yet.

## Upstream attribution and local changes

See `packages/revev_engine/THIRD_PARTY_NOTICES.txt` and `docs/PORTING.md`.
The required core is vendored, so cloning upstream repositories is not needed
to build. `third_party/` is an ignored research checkout from development.
