# GitHub and Play internal testing

Repository: https://github.com/MrBendel/RevEV (public).
Android package: `com.platypus.revev`. Keep this identity after registering with Play.
RevEV is a free app. This workflow targets internal testers only.

## Build a signed bundle

GitHub → Actions → **Play internal release** → **Run workflow**, on `main`.
Leave **publish** unchecked. The resulting `revev-play-…` artifact contains a
signed AAB suitable for the first manual Play Console upload. No store release
is created by a build-only run.

Locally, with Flutter, Java and the Android SDK installed:

```powershell
python scripts/setup_signing.py
python scripts/build_release.py --flutter C:\Users\andre\tools\flutter\bin\flutter.bat
```

The bundle is `build/app/outputs/bundle/release/app-release.aab`.
`build/release.json` records its version code. Debug builds still work without
release credentials. Release builds fail when signing is missing; they never
fall back to the debug certificate.

## Upload identity

A dedicated RevEV RSA upload key is stored in ignored `secrets/revev-upload.jks`.
Back it up together with `secrets/android-upload.json` in a secure location.
`android/key.properties` is generated locally and ignored. Never commit these.
Enable Google Play App Signing for the app; Google manages the distribution key
and this key authenticates uploads.

Encrypted GitHub repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEYSTORE_ALIAS`
- `PLAY_STORE_JSON_KEY`

The Play service account is the existing Battle Mahjong publisher. Its credential
is shared for publishing access; the apps have separate upload keys. Grant that
account access specifically to RevEV and permission to release to testing tracks
in Play Console → Users and permissions. Google Cloud IAM alone is insufficient.

## One-time Play setup

1. In the existing Andrew Poes developer account, create **RevEV**, package
   `com.platypus.revev`, English (US), **App**, **Free**. Complete the account owner's
   policy/export declarations.
2. Open **Testing → Internal testing**, create a release, enable Play App Signing
   and upload the first signed AAB manually. Save/review any required setup.
3. Give the existing publisher service account access to RevEV's testing releases.
4. Choose the internal tester list and copy RevEV's own opt-in link. Battle
   Mahjong's tester link does not apply to this app.
5. Set GitHub repository variable `PLAY_PUBLISH_ENABLED` to `true` once the app
   can accept API uploads. It stays disabled until bootstrap is complete.

## Subsequent releases

The workflow has two jobs: **1. Authorize release request** and
**2. Build and publish**. A green authorization job only approves the request;
it does not mean an app was built or uploaded. Open the second job to follow
compilation and **Upload internal release**. Its final summary distinguishes
build-only, failed/cancelled, draft, and successful publishing, and links the
signed bundle artifact when available. A draft is not available to testers.

Node runtime deprecation warnings are not publishing errors. Look for a failed
step or a cancelled job. If publishing fails after the bundle is saved, download
that run's signed artifact for a manual Play upload rather than rebuilding it.

Run **Play internal release** on `main`, check **publish**, and choose `draft` or
`completed`. `draft` prepares a release in Play; `completed` makes it available
on the internal track, subject to Play requirements.

For an open PR or a PR merged into `main` from this repository, a maintainer can comment:

```text
#build-and-deploy
```

This is the standard command, matching Battle Mahjong. It builds that exact PR
head (or its exact merge commit for a merged PR) and publishes a completed internal release. Review the PR before triggering
it. `#deploy-playstore` remains supported as a compatibility alias.
The workflow summary identifies the checked-out source commit and version code,
so a PR build can be traced to the exact revision included in the bundle.
Unlike the older Battle Mahjong workflow, PR descriptions do not trigger releases
and later pushes need a new comment. Fork PRs and callers without write/admin
access cannot request signed releases. Closed, unmerged PRs are also rejected.
For merged PRs, this builds that PR's merge commit, not the latest `main`.
Publishing remains blocked until `PLAY_PUBLISH_ENABLED` is `true`; a comment
does not bypass the initial Play setup requirement.

Release runs are serialized and use UTC seconds since 2020 as the version code.
Never reuse a previously uploaded code; local and CI releases share this scheme.
Normal pushes and PRs run **Android checks** (analysis, tests and debug APK build)
without signing credentials. Release artifacts expire after 14 days.

## Current limits

Store registration and automated delivery do not make this prototype production
ready. It is a manual foreground sound experiment; phone performance, sound
tuning, privacy/store listing declarations and testing requirements must be
completed before a public production launch. No production-track upload is wired.

References: [Flutter Android release guide](https://docs.flutter.dev/deployment/android),
[Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756),
[upload action setup](https://github.com/r0adkll/upload-google-play).
