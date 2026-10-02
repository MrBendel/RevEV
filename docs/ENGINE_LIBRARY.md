# Bundled engine library

Source: https://github.com/ange-yaghi/engine-sim at
`85f7c3b959a908ed5232ede4f1a4ac7eafe6b630` (MIT).
The `assets/engines`, `assets/sound-library`, and `es` scripts/WAV files are
copied into `packages/revev_engine/assets/engine-sim`. The catalog includes the
25 complete engine definitions; radial helper nodes are dependencies, not presets.
The `entries` wrappers import each definition and call its `main` or `set_engine`.
Definitions retain their upstream geometry, firing order, frequency and exhaust IRs.
Startup supplies a brief 8% throttle assist, with starter engagement bounded to
five simulated seconds. The heavy nine-cylinder radial and Merlin V12 instead
crank at closed throttle for up to twelve seconds. Ignition-off runs physics until settled or eight seconds,
then fades for 200 ms. Platform interruptions use immediate stop.

`catalog.json` is the reviewed allowlist and the source of names and gauge ranges.
Run `python scripts/generate_engine_catalog.py`, then `dart format
packages/revev_engine/lib/engine_presets.dart` after changing it. Native ID lookup
rejects arbitrary paths. When shipping changed assets, bump `engine-library-v1`
in the Android plugin so a previous install extracts the new library.

## Compiler port

Piranha is vendored at engine-sim's pinned submodule revision
`432f0b122bb1663b686c553c7e7269300afac3bc` from
https://github.com/ange-yaghi/piranha. Its MIT license is reproduced in
`native/vendor/piranha/LICENSE` and the app's third-party notices. The pinned
revision predates that license file; the notice comes from the same upstream
project's published LICENSE.

Local changes replace Boost paths with C++17 filesystem, use POSIX allocation,
make compiler output thread-local, accept CRLF scripts, correct a shadowed template
parameter, and track script-created supporting objects across repeated sessions.
The mobile host supplies the library root and decodes mono 44.1 kHz PCM IR files
on the simulation worker. IR length is capped at 10,000 samples, as upstream does.

Generated parser/scanner sources are committed so Android/iOS builds need neither
Flex nor Bison. Generated with WinFlexBison 2.5.25 (Bison 3.8.2, Flex 2.6.4):

```powershell
win_bison --defines=packages/revev_engine/native/vendor/piranha/generated/parser.auto.h -o packages/revev_engine/native/vendor/piranha/generated/parser.auto.cpp packages/revev_engine/native/vendor/piranha/flex-bison/specification.y
win_flex -o packages/revev_engine/native/vendor/piranha/generated/scanner.auto.cpp packages/revev_engine/native/vendor/piranha/flex-bison/scanner.l
```

Do not pass `--wincompat`: the generated scanner targets Android/iOS POSIX APIs.
`FlexLexer.h` is copied from the same distribution. License notices and Bison's
parser-skeleton exception are retained in generated sources and app credits.

## Validation

`revev_preset_smoke <asset-root>` compiles every bundled definition, verifies its
cylinder count and decodes every referenced exhaust response.
`revev_smoke <asset-root> <preset-id>` checks finite bounded PCM, idle/rev response
and ignition-off completion. Without a selected preset it also exercises restart.
Flutter tests cover selection forwarding, control locking during coast-down,
diagnostic state and the automated test. The Android integration test starts the
Porsche 911 Carrera definition, revs, waits for coast-down, then switches to the Porsche 911 Turbo definition.
iOS changes require a Mac build and device verification.
