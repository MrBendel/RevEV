import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dashboard.dart';

import 'package:flutter/material.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['engine-sim', 'simple-2d-constraint-solver'],
      await rootBundle.loadString(
        'packages/revev_engine/THIRD_PARTY_NOTICES.txt',
      ),
    );
  });
  runApp(const RevEvApp());
}

class RevEvApp extends StatelessWidget {
  const RevEvApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RevEV',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff171716),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffd3c6ac),
        brightness: Brightness.dark,
        primary: const Color(0xffd3c6ac),
      ),
    ),
    home: const EngineLab(),
  );
}

class EngineLab extends StatefulWidget {
  const EngineLab({super.key});
  @override
  State<EngineLab> createState() => _EngineLabState();
}

class _EngineLabState extends State<EngineLab> with WidgetsBindingObserver {
  final _engine = RevevEngine();
  Timer? _poll;
  EngineStats _stats = const EngineStats();
  double _throttle = 0, _volume = 0.15;
  bool _busy = false, _polling = false;
  int _session = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    if (_polling || _busy || !_stats.playing) return;
    _polling = true;
    final session = _session;
    try {
      final stats = await _engine.stats();
      if (mounted && session == _session && !_busy) {
        setState(() {
          _stats = stats;
          if (!stats.playing) _throttle = 0;
          if (stats.failed) {
            _error = 'Engine or audio output stopped. Tap Start to try again.';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Unable to read engine status: $e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final session = ++_session;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_stats.playing) {
        await _engine.stop();
        if (mounted) {
          setState(() {
            _stats = const EngineStats();
            _throttle = 0;
          });
        }
      } else {
        _throttle = 0;
        await _engine.controls(0, _volume);
        if (!mounted || session != _session) return;
        await _engine.start();
        if (!mounted || session != _session) {
          await _engine.stop();
          return;
        }
        if (mounted) setState(() => _stats = const EngineStats(playing: true));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stats = const EngineStats();
          _error = 'Could not start the engine: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _controls() async {
    try {
      await _engine.controls(_throttle, _volume);
    } catch (e) {
      if (mounted) setState(() => _error = 'Controls unavailable: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_pause());
    }
  }

  Future<void> _pause() async {
    ++_session;
    try {
      await _engine.stop();
    } catch (_) {
      /* Engine may already be detached. */
    }
    if (mounted) {
      setState(() {
        _stats = const EngineStats();
        _throttle = 0;
      });
    }
  }

  @override
  void dispose() {
    ++_session;
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_engine.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LeatherSurface(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 20,
                ),
                children: [
                  Row(
                    children: [
                      const Text(
                        'RevEV',
                        style: TextStyle(
                          fontSize: 27,
                          letterSpacing: 3,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          color: ivory,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _stats.playing
                              ? const Color(0xffa5b889)
                              : leatherMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _stats.playing ? 'ENGINE RUNNING' : 'ENGINE OFF',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.6,
                            color: leatherMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'THE SOUND OF MOTION',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 2.8,
                      color: leatherMuted,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const StitchLine(),
                  const SizedBox(height: 27),
                  const Center(
                    child: Text(
                      'THE INSTRUMENT ROOM',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2.6,
                        color: leatherMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  InstrumentCluster(
                    rpm: _stats.rpm,
                    throttle: _throttle,
                    volume: _volume,
                    running: _stats.playing,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 22,
                        height: 1,
                        color: const Color(0xff635b4e),
                      ),
                      const Flexible(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 13),
                          child: FittedBox(
                            child: Text(
                              '2.0  /  INLINE FOUR',
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 2,
                                color: ivory,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 22,
                        height: 1,
                        color: const Color(0xff635b4e),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Center(
                    child: Text(
                      'Naturally aspirated. Digitally alive.',
                      style: TextStyle(fontSize: 11, color: leatherMuted),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xff8f897d),
                            Color(0xff292926),
                            Color(0xff69655c),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 82,
                        height: 82,
                        child: FilledButton(
                          key: const Key('start'),
                          onPressed: _busy ? null : _toggle,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: const Color(0xff242321),
                            foregroundColor: ivory,
                            shape: CircleBorder(
                              side: BorderSide(
                                color: _stats.playing
                                    ? needleRed
                                    : const Color(0xff5d5548),
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.power_settings_new,
                                size: 20,
                                color: _stats.playing ? needleRed : ivory,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _busy
                                    ? 'WAIT'
                                    : _stats.playing
                                    ? 'STOP'
                                    : 'START',
                                style: const TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Text(
                                'ENGINE',
                                style: TextStyle(
                                  fontSize: 8,
                                  letterSpacing: 1.2,
                                  color: leatherMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xffffb49e)),
                      ),
                    ),
                  const SizedBox(height: 26),
                  const StitchLine(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Text(
                        'THROTTLE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: ivory,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(_throttle * 100).round()}%',
                        style: const TextStyle(
                          color: leatherMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: needleRed,
                      thumbColor: ivory,
                      inactiveTrackColor: const Color(0xff3c3934),
                    ),
                    child: Slider(
                      key: const Key('throttle'),
                      value: _throttle,
                      semanticFormatterCallback: (v) =>
                          'Throttle ${(v * 100).round()} percent',
                      onChanged: _stats.playing && !_busy
                          ? (v) {
                              setState(() => _throttle = v);
                              _controls();
                            }
                          : null,
                    ),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'IDLE',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1,
                          color: leatherMuted,
                        ),
                      ),
                      Text(
                        'FULL THROTTLE',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1,
                          color: leatherMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 23),
                  Row(
                    children: [
                      const Icon(
                        Icons.volume_down_outlined,
                        size: 20,
                        color: leatherMuted,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'OUTPUT',
                        style: TextStyle(fontSize: 10, letterSpacing: 2),
                      ),
                      Expanded(
                        child: Slider(
                          key: const Key('volume'),
                          value: _volume,
                          semanticFormatterCallback: (v) =>
                              'Volume ${(v * 100).round()} percent',
                          onChanged: (v) {
                            setState(() => _volume = v);
                            _controls();
                          },
                        ),
                      ),
                      Text(
                        '${(_volume * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: leatherMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'MANUAL SOUND TEST',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 2,
                      color: leatherMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pauses when you leave the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: leatherMuted),
                  ),
                  const SizedBox(height: 18),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Engine diagnostics',
                      style: TextStyle(fontSize: 12, color: leatherMuted),
                    ),
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${_stats.workMs.toStringAsFixed(1)} ms per 10 ms audio block',
                        ),
                        subtitle: Text(
                          '${_stats.underruns} buffer underruns since start.\nIncludes startup. Speaker latency is not measured.',
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'RevEV',
                    ),
                    child: const Text(
                      'Open-source credits',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
