# Android audio-focus fixture

This separate, test-only APK requests eight alternating transient/duckable
interruptions (2.5 seconds held, 4.5 seconds released). It is not bundled in RevEV.
The foreground notification is silent. Target SDK 28 allows this test service
to request focus independently of the app under test.

Build from the repository root in PowerShell (Java and Android SDK required):

```powershell
$out = Join-Path (Get-Location) 'build/audio-focus-fixture'
$sdk = "$env:LOCALAPPDATA/Android/Sdk"
$bt = "$sdk/build-tools/36.0.0"
$jar = "$sdk/platforms/android-36/android.jar"
New-Item -ItemType Directory -Force "$out/classes" | Out-Null
javac -source 8 -target 8 -classpath $jar -d "$out/classes" test_support/audio_focus_fixture/FocusService.java
& "$bt/d8.bat" --lib $jar --output $out "$out/classes/dev/revev/audiofixture/FocusService.class"
& "$bt/aapt2.exe" link --manifest test_support/audio_focus_fixture/AndroidManifest.xml -I $jar -o "$out/unsigned.apk"
jar uf "$out/unsigned.apk" -C $out classes.dex
& "$bt/apksigner.bat" sign --ks "$env:USERPROFILE/.android/debug.keystore" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out "$out/fixture.apk" "$out/unsigned.apk"
& "$sdk/platform-tools/adb.exe" -s emulator-5554 install -r "$out/fixture.apk"
```

After the audio harness logs `AUDIO_SOAK_READY`:

```powershell
& "$sdk/platform-tools/adb.exe" -s emulator-5554 shell am start-foreground-service -n dev.revev.audiofixture/.FocusService
& "$sdk/platform-tools/adb.exe" -s emulator-5554 logcat -d -s RevEVFocusFixture:I '*:S'
```

After testing, uninstall `dev.revev.audiofixture` from the emulator.
