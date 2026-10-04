# Driving test lab

The lab below the controls in **SPEED SIM** and **GPS DRIVE** separates two questions:
does the engine respond to known driving inputs, and is the phone receiving useful
inputs in its actual mounting position?

## Repeatable stationary scenarios

Select an engine, output level, and shift aggressiveness with the engine stopped.
Choose **SPEED SIM**, scroll to **Driving test lab**, and select a scenario:

| Scenario | Sequence |
| --- | --- |
| City launch | 3 s idle, 0–30 mph over 10 s, 5 s cruise, 6 s braking, 3 s stopped |
| Brisk launch | Same phases, with 0–60 mph over 10 s |
| GPS gap | City launch with GPS withheld from seconds 7–13 |

Each scenario starts a fresh native engine session and waits for at least 700 RPM
before starting the driving profile (a 45-second timeout preserves a failed-start
report). Acceleration inputs update
with the foreground poll (nominally 150 ms), and GPS speed observations arrive
approximately once per second. Both pass through the same Android speed estimator
as live driving, then the real native transmission and engine simulation. The
initial 3 seconds allow the engine to start. Completion or cancellation stops the
engine; the trace remains available until the next recording or app restart.

Watch speed, RPM and gears, and listen for launch, shifts, cruise and overrun.
The result shows peak RPM/speed, largest sampled speed error, and estimated speed
alongside actual engine RPM and gear output. **Copy drive report** exports timestamped inputs, motion
diagnostics, RPM, gear, acceleration, boost and underruns as JSON. A response
summary is an observation, not a pass/fail certification of sound quality.

Synthetic acceleration is already in vehicle coordinates. These tests cover
speed estimation and the drivetrain, but do **not** exercise Android's GPS radio,
gravity removal, or mounting-axis transforms. Use live recording for those.

## Capture a real drive

1. While parked, choose **Phone mounting** with the engine stopped. For a flat
   phone with its top toward the dashboard, use **Tray · top toward dashboard**.
   Select the corresponding manual option if the phone is sideways or reversed.
   Auto detects broad tilt from gravity; it cannot infer a flat phone's heading.
2. Choose **GPS DRIVE**, allow location access, and enable the phone's location
   service. Precise location is preferable for speed observations. Start the
   engine and scroll to **Driving test lab**.
3. Check location permission, GPS provider state, sensor age, GPS age, and the
   effective mount. A permission grant alone is not evidence of a GPS fix.
4. Tap **Record live drive** before moving. The recording lasts up to 3 minutes
   or 1,200 samples. Use ordinary acceleration, cruise and braking; have a
   passenger observe the screen if needed. This is not a request to perform a
   0–60 road run.
5. After parking, finish the recording and copy the report. The graph and report
   survive Stop or a background interruption within the current app session.
   Backgrounding still stops audio and ends the recording; background service
   and Android Auto lifecycle work is separate from this harness.

No location coordinates are captured in the report. It stays in memory until
copied; it is not automatically uploaded or saved across app restarts.

## Interpreting a failed drive

| Observation | Where to investigate |
| --- | --- |
| GPS age is absent; rejected fixes increase | No usable speed fix. Position-only, inaccurate, old and out-of-order observations are rejected. |
| GPS provider off or location denied | Phone location settings / permission. |
| Sensor age absent or old | Accelerometer registration, availability or app lifecycle. |
| Device X/Y/Z changes but forward acceleration has the wrong sign or stays small | Mount selection, gravity reference and phone orientation. |
| Fused speed rises but RPM stays near idle | Native drivetrain/engine response; compare the stationary scenario on the same preset. |
| RPM responds but sound is absent or choppy | Output routing, volume, audio focus and debug-dashboard underruns. |
| Trace ends with a background interruption | Phone foreground/audio lifecycle, including when using the car display. |

The estimator anchors speed to accepted GPS observations and integrates forward
acceleration between fixes. It uses GPS-derived acceleration when the IMU is
missing or stale, rather than adding both accelerations together. It accepts
speed-bearing fixes up to 2.5 seconds old with position accuracy within 50 m,
rejects duplicate/out-of-order timestamps, and holds estimated speed after a
5-second GPS gap to bound drift. These are initial tuning limits, not a claim of
navigation-grade accuracy. The gap scenario deliberately exposes the held-speed
state and recovery on the next accepted GPS observation.

## Developer checks

```powershell
flutter analyze
flutter test
cd android
.\gradlew.bat :revev_engine:testDebugUnitTest
cd ..
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/drive_harness_test.dart -d <android-id>
```

Android unit tests exercise the actual estimator, including missing sensors,
rejected fixes, braking, bounded drift and recovery. Flutter tests cover scenario
profiles, bounded reports, native packet dispatch and interruption paths. The
device integration test runs launch and GPS-gap scenarios against the native
engine and checks RPM, shifts and stopping. Emulator performance and synthetic
inputs cannot validate the physical phone mount or in-car audio route.
