import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dashboard.dart';
import 'debug_dashboard.dart';
import 'mounting_position.dart';

import 'package:flutter/material.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['engine-sim', 'simple-2d-constraint-solver', 'Piranha', 'Flex/Bison'],
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
  final _debug = DebugSession();
  final _sessionClock = Stopwatch();
  Timer? _poll;
  Timer? _testTimer;
  int _testGeneration = 0;
  bool _testing = false;
  String? _testPhase;
  DriveMode _driveMode = DriveMode.manual;
  double _shiftAggressiveness = 0.6;
  double _tireSquealSensitivity = 0.5;
  double _simulatedSpeedKmh = 0.0;
  double _simulatedLateralG = 0.0;
  double _lastSimSpeed = 0.0;
  DateTime _lastSpeedTime = DateTime.now();
  EngineStats _stats = const EngineStats();
  String _preset = 'porsche/911_carrera_32';
  MountingPosition _mountingPosition = MountingPosition.trayTopForward;
  ListeningMode _listeningMode = ListeningMode.original;
  double _rumbleStrength = 0.5;
  bool _mixBusy = false;
  double _throttle = 0, _volume = 0.15;
  bool _busy = false, _polling = false;
  int _session = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine.setRemoteCommandHandler(
      onRemoteStart: (preset) {
        if (!_stats.playing && !_busy) {
          setState(() => _preset = preset);
          unawaited(_toggle());
        }
      },
      onRemoteStop: () {
        if (_stats.playing && !_busy) {
          unawaited(_toggle(immediate: true));
        }
      },
      onRemoteSetPreset: (preset) {
        if (!_stats.playing && !_busy) {
          setState(() => _preset = preset);
        }
      },
      onRemoteSetDriveMode: (mode) {
        setState(() => _driveMode = mode);
        unawaited(_sendDriveTelemetry());
      },
      onRemoteSetAggressiveness: (aggr) {
        setState(() => _shiftAggressiveness = aggr);
        unawaited(_sendDriveTelemetry());
      },
    );
    _poll = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _refresh(),
    );
  }

  Future<void> _sendDriveTelemetry() async {
    final now = DateTime.now();
    final dt = now.difference(_lastSpeedTime).inMilliseconds / 1000.0;
    _lastSpeedTime = now;
    double accel = 0.0;
    if (_driveMode == DriveMode.simDrive) {
      if (dt > 0.001) {
        accel = ((_simulatedSpeedKmh - _lastSimSpeed) / 3.6) / dt;
      }
      _lastSimSpeed = _simulatedSpeedKmh;
    }
    final speedMps = _driveMode == DriveMode.simDrive
        ? _simulatedSpeedKmh / 3.6
        : 0.0;
    final lateralAccel = _driveMode == DriveMode.simDrive
        ? _simulatedLateralG * 9.80665
        : 0.0;
    try {
      await _engine.driveTelemetry(
        speedMps: speedMps,
        accelMps2: accel,
        aggressiveness: _shiftAggressiveness,
        driveMode: _driveMode,
        mountingPosition: _mountingPosition.name,
        lateralAccelMps2: lateralAccel,
        tireSquealSensitivity: _tireSquealSensitivity,
      );
    } catch (_) {}
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
          _debug.record(stats, _sessionClock.elapsed);
          if (!stats.playing) _sessionClock.stop();
          if (!stats.playing) _throttle = 0;
          if (!stats.playing) {
            _cancelTest(stats.failed ? 'Failed' : 'Interrupted');
          }
          if (stats.failed) {
            _error = 'Engine or audio output stopped. Tap Start to try again.';
            _debug.error = _error;
          }
        });
        if (_stats.playing && _driveMode == DriveMode.simDrive) {
          await _sendDriveTelemetry();
        }
      }
    } catch (e) {
      if (mounted && session == _session && !_busy) {
        setState(() {
          _error = 'Unable to read engine status: $e';
          _debug.error = _error;
        });
        if (_testing) {
          _cancelTest('Failed: diagnostics unavailable');
          await _toggle(immediate: true);
        }
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _toggle({bool immediate = false}) async {
    if (_busy || (_stats.stopping && !immediate)) return;
    final session = ++_session;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_stats.playing) {
        _cancelTest('Cancelled');
        if (immediate) {
          await _engine.stop();
        } else {
          await _engine.shutdown();
        }
        if (mounted) {
          setState(() {
            _stats = immediate
                ? const EngineStats()
                : EngineStats(
                    playing: true,
                    stopping: true,
                    rpm: _stats.rpm,
                    workMs: _stats.workMs,
                    underruns: _stats.underruns,
                    boost: _stats.boost,
                  );
            if (immediate) {
              _finishDebug('Stopped');
            } else {
              _debug.status = 'Coasting down';
            }
            _throttle = 0;
          });
        }
      } else {
        _debug.begin();
        _debug.preset = _preset;
        _debug.mountingPosition = _mountingPosition.name;
        _sessionClock
          ..reset()
          ..start();
        _throttle = 0;
        await _sendListeningMix();
        if (!mounted || session != _session) return;
        await _sendDriveTelemetry();
        if (!mounted || session != _session) return;
        await _engine.controls(0, _volume);
        if (!mounted || session != _session) return;
        await _engine.start(preset: _preset);
        if (!mounted || session != _session) {
          await _engine.stop();
          return;
        }
        if (mounted) {
          setState(() {
            _stats = const EngineStats(playing: true);
            _debug.status = 'Running';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stats = const EngineStats();
          _error = 'Could not start the engine: $e';
          _debug.error = _error;
          _finishDebug('Failed');
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

  Future<void> _sendListeningMix() async {
    final mode = _listeningMode;
    final strength = _rumbleStrength;
    await _engine.listeningMix(mode, strength);
    if (_sessionClock.isRunning) {
      if (_debug.listeningChanges.length == 128) {
        _debug.listeningChanges.removeAt(0);
      }
      _debug.listeningChanges.add({
        'elapsedMs': _sessionClock.elapsedMilliseconds,
        'mode': mode.name,
        'strength': strength,
      });
    }
  }

  Future<void> _changeListeningMix(ListeningMode mode, double strength) async {
    if (_mixBusy) return;
    final previousMode = _listeningMode;
    final previousStrength = _rumbleStrength;
    setState(() {
      _mixBusy = true;
      _listeningMode = mode;
      _rumbleStrength = strength;
    });
    try {
      await _sendListeningMix();
    } catch (e) {
      if (mounted) {
        setState(() {
          _listeningMode = previousMode;
          _rumbleStrength = previousStrength;
          _error = 'Could not change listening mode: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _mixBusy = false);
    }
  }

  Future<void> _runTest() async {
    if (_busy || _testing || _stats.playing) return;
    final generation = ++_testGeneration;
    setState(() {
      _testing = true;
      _testPhase = 'Starting test';
    });
    await _toggle();
    if (!mounted || generation != _testGeneration) return;
    if (!_stats.playing) {
      setState(() => _cancelTest('Failed to start'));
      return;
    }
    await _advanceTest(0, generation);
  }

  Future<void> _advanceTest(int phase, int generation) async {
    if (!mounted || !_testing || generation != _testGeneration) return;
    if (phase == 0 && _stats.rpm < 600) {
      await _refresh();
      if (!mounted || !_testing || generation != _testGeneration) return;
      if (_stats.rpm < 600) {
        if (_sessionClock.elapsed > const Duration(seconds: 30)) {
          _cancelTest('Failed: engine did not start');
          await _toggle(immediate: true);
        } else {
          _testTimer = Timer(
            const Duration(milliseconds: 150),
            () => unawaited(_advanceTest(0, generation)),
          );
        }
        return;
      }
    }
    if (phase == 3) {
      await _refresh();
      if (!mounted || !_testing || generation != _testGeneration) return;
      _cancelTest('Completed');
      await _toggle();
      return;
    }
    const names = ['Initial idle', 'Rev at 35%', 'Return to idle'];
    final throttle = phase == 1 ? 0.35 : 0.0;
    try {
      await _engine.controls(throttle, _volume);
      if (!mounted || !_testing || generation != _testGeneration) return;
      setState(() {
        _throttle = throttle;
        _testPhase = '${names[phase]} · phase ${phase + 1}/3';
        _debug.testResult = 'Running';
        _debug.testPhases.add({
          'phase': names[phase],
          'elapsedMs': _sessionClock.elapsedMilliseconds,
          'throttle': throttle,
          'volume': _volume,
        });
      });
      _testTimer = Timer(
        const Duration(seconds: 5),
        () => unawaited(_advanceTest(phase + 1, generation)),
      );
    } catch (e) {
      if (!mounted || generation != _testGeneration) return;
      _debug.error = 'Test controls failed: $e';
      _cancelTest('Failed: controls unavailable');
      await _toggle(immediate: true);
    }
  }

  void _cancelTest(String result) {
    if (!_testing) return;
    ++_testGeneration;
    _testTimer?.cancel();
    _testTimer = null;
    _testing = false;
    _testPhase = null;
    _debug.testResult = result;
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
    _cancelTest('Cancelled on background');
    _finishDebug('Stopped on background');
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

  void _finishDebug(String status) {
    _sessionClock.stop();
    if (_debug.startedAt != null) {
      _debug.elapsed = _sessionClock.elapsed;
      _debug.status = status;
    }
  }

  @override
  void dispose() {
    ++_session;
    _cancelTest('Cancelled');
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
                          _stats.stopping
                              ? 'COASTING DOWN'
                              : _stats.playing
                              ? 'ENGINE RUNNING'
                              : 'ENGINE OFF',
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
                  const SizedBox(height: 12),
                  const StitchLine(),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('engine-preset'),
                    initialValue: _preset,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Engine',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final preset in enginePresets)
                        DropdownMenuItem(
                          value: preset.id,
                          child: Text(
                            preset.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _stats.playing || _busy || _testing
                        ? null
                        : (value) {
                            if (value != null) setState(() => _preset = value);
                          },
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final activePreset = enginePresets.firstWhere(
                        (p) => p.id == _preset,
                        orElse: () => enginePresets.first,
                      );
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InstrumentCluster(
                            rpm: _stats.rpm,
                            maxRpm: activePreset.maxRpm,
                            throttle: _throttle,
                            volume: _volume,
                            running: _stats.playing,
                            isTurbo: activePreset.isTurbo,
                            boost: _stats.boost,
                            gear: _stats.gear,
                            speedKmh: _driveMode == DriveMode.simDrive
                                ? _simulatedSpeedKmh
                                : _stats.speedKmh,
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
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                  ),
                                  child: FittedBox(
                                    child: Text(
                                      activePreset.name,
                                      style: const TextStyle(
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
                          if (_stats.playing && _driveMode != DriveMode.manual)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xff242726),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xff5d5548),
                                      ),
                                    ),
                                    child: Text(
                                      _stats.gear > 0
                                          ? 'GEAR ${_stats.gear} / ${activePreset.gearCount}'
                                          : 'NEUTRAL',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.8,
                                        color: ivory,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xff242726),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xff5d5548),
                                      ),
                                    ),
                                    child: Text(
                                      '${(_driveMode == DriveMode.simDrive ? _simulatedSpeedKmh * 0.621371 : _stats.speedMph).round()} MPH · ${(_driveMode == DriveMode.simDrive ? _simulatedSpeedKmh : _stats.speedKmh).round()} KM/H',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.2,
                                        color: leatherMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 7),
                          Center(
                            child: Text(
                              activePreset.isTurbo
                                  ? 'Turbocharged. Digitally alive.'
                                  : 'Naturally aspirated. Digitally alive.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: leatherMuted,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                   const SizedBox(height: 14),
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
                          onPressed: _busy || _stats.stopping ? null : _toggle,
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
                                    : _stats.stopping
                                    ? 'STOPPING'
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
                  const SizedBox(height: 12),
                  const StitchLine(),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Text(
                        'DRIVE MODE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: ivory,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<DriveMode>(
                    key: const Key('drive-mode'),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: DriveMode.manual,
                        label: Text('MANUAL REV'),
                        icon: Icon(Icons.tune, size: 16),
                      ),
                      ButtonSegment(
                        value: DriveMode.gpsDrive,
                        label: Text('GPS DRIVE'),
                        icon: Icon(Icons.speed, size: 16),
                      ),
                      ButtonSegment(
                        value: DriveMode.simDrive,
                        label: Text('SPEED SIM'),
                        icon: Icon(Icons.sports_esports, size: 16),
                      ),
                    ],
                    selected: {_driveMode},
                    onSelectionChanged: _busy || _testing
                        ? null
                        : (set) {
                            setState(() => _driveMode = set.first);
                            _sendDriveTelemetry();
                          },
                  ),
                  const SizedBox(height: 10),
                  if (_driveMode != DriveMode.manual) ...[
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'SHIFT AGGRESSIVENESS',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: ivory,
                            ),
                          ),
                        ),
                        Text(
                          _shiftAggressiveness < 0.35
                              ? 'ECO · ${(_shiftAggressiveness * 100).round()}%'
                              : _shiftAggressiveness < 0.75
                              ? 'SPORT · ${(_shiftAggressiveness * 100).round()}%'
                              : 'RACE · ${(_shiftAggressiveness * 100).round()}%',
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
                        key: const Key('shift-aggressiveness'),
                        value: _shiftAggressiveness,
                        onChanged: (v) {
                          setState(() => _shiftAggressiveness = v);
                          _sendDriveTelemetry();
                        },
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ECO', style: TextStyle(fontSize: 9, color: leatherMuted)),
                        Text('SPORT', style: TextStyle(fontSize: 9, color: leatherMuted)),
                        Text('RACE', style: TextStyle(fontSize: 9, color: leatherMuted)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'TIRE SQUEAL SENSITIVITY',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: ivory,
                            ),
                          ),
                        ),
                        Text(
                          _tireSquealSensitivity <= 0.05
                              ? 'OFF'
                              : _tireSquealSensitivity < 0.4
                              ? 'LOW · ${(_tireSquealSensitivity * 100).round()}%'
                              : _tireSquealSensitivity < 0.75
                              ? 'MED · ${(_tireSquealSensitivity * 100).round()}%'
                              : 'HIGH · ${(_tireSquealSensitivity * 100).round()}%',
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
                        key: const Key('tire-squeal-sensitivity'),
                        value: _tireSquealSensitivity,
                        onChanged: (v) {
                          setState(() => _tireSquealSensitivity = v);
                          _sendDriveTelemetry();
                        },
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('OFF', style: TextStyle(fontSize: 9, color: leatherMuted)),
                        Text('BALANCED', style: TextStyle(fontSize: 9, color: leatherMuted)),
                        Text('TRACK', style: TextStyle(fontSize: 9, color: leatherMuted)),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_driveMode == DriveMode.simDrive) ...[
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'SIMULATED SPEED',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: ivory,
                            ),
                          ),
                        ),
                        Text(
                          '${(_simulatedSpeedKmh * 0.621371).round()} MPH · ${_simulatedSpeedKmh.round()} KM/H',
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
                        key: const Key('sim-speed'),
                        value: _simulatedSpeedKmh,
                        max: 180.0,
                        divisions: 36,
                        onChanged: _stats.playing && !_stats.stopping && !_busy && !_testing
                            ? (v) {
                                setState(() => _simulatedSpeedKmh = v);
                                _sendDriveTelemetry();
                              }
                            : null,
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0 MPH', style: TextStyle(fontSize: 9, color: leatherMuted)),
                        Text('55 MPH', style: TextStyle(fontSize: 9, color: leatherMuted)),
                        Text('112 MPH', style: TextStyle(fontSize: 9, color: leatherMuted)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'SIMULATED LATERAL G',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: ivory,
                            ),
                          ),
                        ),
                        Text(
                          '${_simulatedLateralG.toStringAsFixed(2)} G',
                          style: TextStyle(
                            color: _stats.tireSquealLevel > 0.05 ? needleRed : leatherMuted,
                            fontSize: 12,
                            fontWeight: _stats.tireSquealLevel > 0.05 ? FontWeight.bold : FontWeight.normal,
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
                        key: const Key('sim-lateral-g'),
                        value: _simulatedLateralG,
                        max: 1.5,
                        divisions: 30,
                        onChanged: _stats.playing && !_stats.stopping && !_busy && !_testing
                            ? (v) {
                                setState(() => _simulatedLateralG = v);
                                _sendDriveTelemetry();
                              }
                            : null,
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0.0 G', style: TextStyle(fontSize: 9, color: leatherMuted)),
                        Text('0.75 G', style: TextStyle(fontSize: 9, color: leatherMuted)),
                        Text('1.50 G', style: TextStyle(fontSize: 9, color: leatherMuted)),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_driveMode == DriveMode.gpsDrive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xff22211f),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xff3f3c36)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.gps_fixed, size: 16, color: Color(0xffa5b889)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Automatic transmission driven by phone GPS speed & accelerometer g-force.',
                              style: TextStyle(fontSize: 11, color: leatherMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
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
                      onChanged:
                          _stats.playing &&
                              !_stats.stopping &&
                              !_busy &&
                              !_testing
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
                  const SizedBox(height: 12),
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
                          onChanged: _testing
                              ? null
                              : (v) {
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
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ListeningMode>(
                    key: const Key('listening-mode'),
                    initialValue: _listeningMode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Listening mode',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final mode in ListeningMode.values)
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                    ],
                    onChanged: _testing || _busy || _mixBusy || _stats.stopping
                        ? null
                        : (mode) {
                            if (mode != null) {
                              unawaited(
                                _changeListeningMix(mode, _rumbleStrength),
                              );
                            }
                          },
                  ),
                  if (_listeningMode == ListeningMode.cabinRumble) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Rumble strength · ${(_rumbleStrength * 100).round()}%',
                    ),
                    Slider(
                      key: const Key('rumble-strength'),
                      value: _rumbleStrength,
                      semanticFormatterCallback: (v) =>
                          'Rumble ${(v * 100).round()} percent',
                      onChanged:
                          _testing || _busy || _mixBusy || _stats.stopping
                          ? null
                          : (v) => unawaited(
                              _changeListeningMix(_listeningMode, v),
                            ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    'Compare at the same throttle and output. Best heard on headphones or car speakers.',
                    style: TextStyle(fontSize: 11, color: leatherMuted),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'MANUAL SOUND TEST',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 2,
                      color: leatherMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pauses when you leave the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: leatherMuted),
                  ),
                  const SizedBox(height: 10),
                  DebugDashboard(
                    session: _debug,
                    testPhase: _testPhase,
                    onRunTest: !_stats.playing && !_busy && !_testing
                        ? () => unawaited(_runTest())
                        : null,
                    onCancelTest: _testing && !_busy
                        ? () => unawaited(_toggle())
                        : null,
                  ),
                  ExpansionTile(
                    key: const Key('mounting-settings'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Phone mounting'),
                    subtitle: Text(_mountingPosition.label),
                    children: [
                      DropdownButtonFormField<MountingPosition>(
                        key: const Key('mounting-position'),
                        initialValue: _mountingPosition,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Mounting position',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final position in MountingPosition.values)
                            DropdownMenuItem(
                              value: position,
                              child: Text(
                                position.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _stats.playing || _busy || _testing
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _mountingPosition = value);
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      Text(_mountingPosition.description),
                      const SizedBox(height: 8),
                      const Text(
                        'Recorded in your test report for this app session. '
                        'Motion control and calibration are not active yet. '
                        'Choose a position before starting the engine.',
                        style: TextStyle(fontSize: 11, color: leatherMuted),
                      ),
                      const SizedBox(height: 16),
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
