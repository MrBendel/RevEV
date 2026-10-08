# Driving test lab

The lab below the controls in **SPEED SIM** and **GPS DRIVE** separates two questions:
does the engine respond to known driving inputs, and is the phone receiving useful
inputs in its actual mounting position?

## Automatic session files

Every engine start creates a separate JSON Lines (`.jsonl`) file in Android's
private `files/session-logs` directory. Recording runs in all drive modes without
pressing the lab's record button. Stop closes the file after engine coast-down;
backgrounding, audio loss, and engine failures also close the session.

With the engine stopped, open **Session logs** below the debug dashboard, select
a recording, and choose a destination in Android's file picker. Exported files
can be attached for analysis. Originals remain across app restarts and updates;
clearing app data or uninstalling removes them. Nothing uploads automatically.

The first line contains UTC start time, preset and settings. Sample lines contain
monotonic elapsed seconds, actual RPM, gear, speed/acceleration fed to the engine,
manual throttle, and the full motion diagnostics (GPS speed/age/accuracy, linear
acceleration axes, forward acceleration, fused speed, mounting choice, requested
RPM and applied engine throttle). The last line records stop reason and count.
Settings are repeated per sample so mode and control changes can be correlated.

These are diagnostic snapshots at approximately 150 ms intervals, not a full-rate
raw sensor trace; actual timing is in each sample. Files flush about once a second
and on stop, without the lab recording's three-minute limit. After an abrupt
process kill, complete JSON lines remain usable even if the final line or stop
record is absent. Disk errors appear beside **Session logs** and do not stop audio.

## Repeatable stationary scenarios

Select an engine, output level, and shift aggressiveness with the engine stopped.
Choose **SPEED SIM**, scroll to **Driving test lab**, and select a scenario:

| Scenario | Sequence |
| --- | --- |
| City launch | 3 s idle, 0–30 mph over 10 s, 5 s cruise, 6 s braking, 3 s stopped |
| Brisk launch | Same phases, with 0–60 mph over 10 s |
| GPS gap | City launch with GPS withheld from seconds 7–13 |
| Steady cruise | 0–15 mph launch, 20 s at steady speed, then braking and stop |
| Motion ripple | Steady-cruise profile with a ±0.8 m/s², 1.5 Hz acceleration disturbance during cruise; GPS speed stays steady |

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

For rhythmic RPM changes, compare **Steady cruise** with **Motion ripple**.
`integration_test/gps_smoothing_test.dart` additionally supplies 1 Hz speed fixes
with matching IMU acceleration and 300 ms delayed fixes while accelerating and
braking. It checks current speed accuracy and RPM direction outside shifts.

Live GPS Drive advances on a 20 ms timer independently of sensor callbacks and
UI polling. A two-state Kalman filter estimates speed and forward accelerometer
bias. Mount/gravity correction and the existing 120 ms acceleration low-pass
filter run upstream. IMU integration gives immediate changes between GPS fixes.
GPS corrects accumulated error using Android speed accuracy when supplied
(default speed standard deviation: 0.5 m/s; position accuracy is only a gate).
A three-second integral history aligns delayed GPS observations to their fix
timestamps. Covariance includes a conservative delay-noise allowance; this is
an approximate delayed-observation filter, not a full navigation INS.

A 250 ms exponential correction removes GPS correction jumps from presented
speed without delaying the IMU response. Corrected IMU acceleration drives load
and shift demand; fresh GPS acceleration is a fallback if IMU data is missing.
IMU samples expire after 500 ms; prediction stops five seconds after the latest
GPS fix. Long scheduling gaps are not integrated. Outage recovery reacquires
speed without learning a false accelerometer bias from unobserved movement.
Diagnostics include corrected acceleration, estimated bias and speed variance.

The Motion ripple scenario deliberately separates steady GPS speed from alternating motion
input, as a stress test rather than a recording of a particular bike or mount.
The report lets you distinguish a changing requested RPM, repeated gear changes,
and an engine that overshoots a steady requested RPM.

The transmission smooths acceleration demand and requires sustained kickdown
input, with at least 0.8 seconds between shifts. In Drive, RPM is computed as
`speedMps * 60 * gearRatio * finalDrive / (2 * pi * tireRadius)`, with an idle
floor, redline ceiling and acceleration-dependent clutch slip below 12 km/h.
At rest, sensor noise cannot raise the idle target. Gear selection and transition
progress are explicit model state: a timestamped input sequence is replayable;
speed and acceleration alone do not uniquely identify a gear.

A bounded 6,000 RPM/s trajectory drives actual crank phase and velocity at every
physics step. Throttle changes engine load/timbre without changing that RPM.
Shift timers and the trajectory use elapsed monotonic time, so slow audio work
does not stretch shift timing. Startup, shutdown and Manual neutral retain free
engine physics. The screen throttle in Drive changes load, not free-rev RPM.

Native validation: build/run `revev_drive_model_test` and
`revev_prescribed_rpm_test`. The latter exercises real combustion/audio with
alternating throttle and verifies crank RPM and phase progression, then releases
the prescription for shutdown. Pass the asset root and preset ID to test a
bundled engine. `integration_test/steady_drive_test.dart` also checks the complete
Android path with steady speed and acceleration ripple.

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
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/steady_drive_test.dart -d <android-id> --profile
```

Android unit tests exercise the actual estimator, including missing sensors,
rejected fixes, braking, bounded drift and recovery. Flutter tests cover scenario
profiles, bounded reports, native packet dispatch and interruption paths. The
device integration test runs launch and GPS-gap scenarios against the native
engine and checks RPM, shifts and stopping. Emulator performance and synthetic
inputs cannot validate the physical phone mount or in-car audio route.
