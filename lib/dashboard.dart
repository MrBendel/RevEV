import 'dart:math' as math;

import 'package:flutter/material.dart';

const ivory = Color(0xffe9e2d4);
const leatherMuted = Color(0xffa39a8b);
const needleRed = Color(0xffcf4936);

class LeatherSurface extends StatelessWidget {
  const LeatherSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: RepaintBoundary(child: CustomPaint(painter: _LeatherPainter())),
      ),
      child,
    ],
  );
}

class _LeatherPainter extends CustomPainter {
  const _LeatherPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff272624), Color(0xff141413), Color(0xff1c1b1a)],
        ).createShader(Offset.zero & size),
    );
    final random = math.Random(47);
    final paint = Paint()..strokeWidth = 0.65;
    // Deterministic grain drawn once behind the instruments; no image assets.
    for (int i = 0; i < size.width * size.height / 32; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final w = 1.5 + random.nextDouble() * 4;
      paint.color = const Color(0xff000000).withValues(alpha: 0.2);
      canvas.drawOval(Rect.fromLTWH(x, y, w, w * 0.45), paint);
      paint.color = const Color(0xffb3a99a).withValues(alpha: 0.055);
      canvas.drawLine(Offset(x, y - 0.6), Offset(x + w, y - 0.1), paint);
    }
  }

  @override
  bool shouldRepaint(_LeatherPainter oldDelegate) => false;
}

class StitchLine extends StatelessWidget {
  const StitchLine({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 12,
    width: double.infinity,
    child: CustomPaint(painter: _StitchPainter()),
  );
}

class _StitchPainter extends CustomPainter {
  const _StitchPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final seam = Paint()
      ..color = const Color(0xff080808)
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 6), Offset(size.width, 6), seam);
    final thread = Paint()
      ..color = const Color(0xffa39880).withValues(alpha: 0.48)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (double x = 1; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, 2), Offset(x + 4.5, 2.7), thread);
      canvas.drawLine(Offset(x, 9), Offset(x + 4.5, 9.7), thread);
    }
  }

  @override
  bool shouldRepaint(_StitchPainter oldDelegate) => false;
}

class InstrumentCluster extends StatelessWidget {
  const InstrumentCluster({
    super.key,
    required this.rpm,
    required this.throttle,
    required this.volume,
    required this.running,
    this.maxRpm = 8000,
    this.isTurbo = false,
    this.boost = 0.0,
    this.gear = 0,
    this.speedKmh = 0.0,
    this.speedMps = 0.0,
    this.accelMps2 = 0.0,
  });
  final double rpm, throttle, volume, maxRpm, boost, speedKmh, speedMps, accelMps2;
  final bool running, isTurbo;
  final int gear;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth;
      final main = width * (isTurbo ? 0.54 : 0.60);
      final small = width * (isTurbo ? 0.28 : 0.32);
      final boostSize = width * 0.30;
      final clusterHeight = isTurbo ? main * 0.68 + boostSize + 16 : main + 20;
      final effectiveSpeedMps = speedMps > 0 ? speedMps : (speedKmh / 3.6);
      return SizedBox(
        height: clusterHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -4,
              top: main * (isTurbo ? 0.46 : 0.52),
              width: small,
              height: small,
              child: AnalogGauge(
                value: throttle * 100,
                max: 100,
                divisions: 5,
                label: 'THROTTLE',
                unit: '%',
                readout: '${(throttle * 100).round()}',
                auxiliary: true,
              ),
            ),
            Positioned(
              right: -4,
              top: main * (isTurbo ? 0.46 : 0.52),
              width: small,
              height: small,
              child: DualSpeedAccelGauge(
                key: const Key('dual-speed-accel-gauge'),
                speedMps: effectiveSpeedMps,
                accelMps2: accelMps2,
                running: running,
              ),
            ),
            if (isTurbo)
              Positioned(
                left: (width - boostSize) / 2,
                top: main * 0.68,
                width: boostSize,
                height: boostSize,
                child: AnalogGauge(
                  key: const Key('boost-gauge'),
                  value: boost.clamp(0.0, 1.5),
                  max: 1.5,
                  divisions: 3,
                  label: 'BOOST',
                  unit: 'bar',
                  readout: running
                      ? '${boost >= 0 ? '+' : ''}${boost.toStringAsFixed(2)}'
                      : '0.00',
                  auxiliary: true,
                ),
              ),
            Positioned(
              left: (width - main) / 2,
              top: 0,
              width: main,
              height: main,
              child: AnalogGauge(
                value: rpm / 1000,
                max: maxRpm / 1000,
                divisions: maxRpm > 10000
                    ? (maxRpm / 2000).round()
                    : (maxRpm / 1000).round(),
                label: 'RevEV',
                unit: '1/min \u00d7 1000',
                readout: running ? rpm.round().toString() : 'READY',
                badge: running ? (gear > 0 ? 'D$gear' : 'N') : null,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class AnalogGauge extends StatelessWidget {
  const AnalogGauge({
    super.key,
    required this.value,
    required this.max,
    required this.divisions,
    required this.label,
    required this.unit,
    required this.readout,
    this.auxiliary = false,
    this.badge,
  });
  final double value, max;
  final int divisions;
  final String label, unit, readout;
  final bool auxiliary;
  final String? badge;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $readout $unit',
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 160),
      builder: (context, animated, child) => CustomPaint(
        painter: _GaugePainter(
          value: animated,
          max: max,
          divisions: divisions,
          label: label,
          unit: unit,
          readout: readout,
          auxiliary: auxiliary,
          badge: badge,
        ),
      ),
    ),
  );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.max,
    required this.divisions,
    required this.label,
    required this.unit,
    required this.readout,
    required this.auxiliary,
    this.badge,
  });
  final double value, max;
  final int divisions;
  final String label, unit, readout;
  final bool auxiliary;
  final String? badge;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final bounds = Offset.zero & size;
    canvas.drawCircle(
      c + Offset(0, r * 0.065),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xff9e9b94),
            Color(0xff33332f),
            Color(0xff0a0a09),
            Color(0xff79766f),
          ],
        ).createShader(bounds),
    );
    canvas.drawCircle(c, r * 0.965, Paint()..color = const Color(0xff141514));
    canvas.drawCircle(c, r * 0.906, Paint()..color = const Color(0xff5f605a));
    canvas.drawCircle(
      c,
      r * 0.892,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.25),
          colors: [Color(0xfff7f2e6), Color(0xffddd8cc), Color(0xffb4b0a6)],
          stops: [0, 0.8, 1],
        ).createShader(bounds),
    );
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    Offset point(double angle, double radius) =>
        c + Offset(math.cos(angle), math.sin(angle)) * radius;
    final tick = Paint()..strokeCap = StrokeCap.butt;
    final count = divisions * 5;
    for (int i = 0; i <= count; ++i) {
      final a = start + sweep * i / count;
      final major = i % 5 == 0;
      tick
        ..color = !auxiliary && i / count > 0.81
            ? needleRed
            : const Color(0xff242726)
        ..strokeWidth = r * (major ? 0.019 : 0.008);
      canvas.drawLine(
        point(a, r * 0.825),
        point(a, r * (major ? 0.73 : 0.78)),
        tick,
      );
      if (major) {
        final tickVal = max * i / count;
        final tickText = max <= 3.0
            ? (tickVal == tickVal.roundToDouble()
                  ? '${tickVal.toInt()}'
                  : tickVal.toStringAsFixed(1))
            : '${tickVal.round()}';
        _text(
          canvas,
          tickText,
          point(a, r * 0.62),
          r * (auxiliary ? 0.155 : 0.19),
          const Color(0xff202322),
          FontWeight.w500,
        );
      }
    }
    _text(
      canvas,
      label,
      c - Offset(0, r * 0.27),
      r * (auxiliary ? 0.115 : 0.13),
      const Color(0xff242726),
      FontWeight.w700,
      italic: !auxiliary,
    );
    _text(
      canvas,
      unit,
      c - Offset(0, r * 0.10),
      r * 0.072,
      const Color(0xff51544d),
      FontWeight.w500,
    );
    final display = Rect.fromCenter(
      center: c + Offset(0, r * 0.59),
      width: r * 0.72,
      height: r * 0.20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(display, Radius.circular(r * 0.06)),
      Paint()..color = const Color(0xff202321),
    );
    _text(
      canvas,
      readout,
      display.center,
      r * 0.13,
      const Color(0xffd9b989),
      FontWeight.w500,
    );
    if (badge != null) {
      final badgeRect = Rect.fromCenter(
        center: c + Offset(0, r * 0.35),
        width: r * 0.32,
        height: r * 0.15,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, Radius.circular(r * 0.04)),
        Paint()..color = const Color(0xff161918),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, Radius.circular(r * 0.04)),
        Paint()
          ..color = const Color(0xff4a4539)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      _text(
        canvas,
        badge!,
        badgeRect.center,
        r * 0.10,
        needleRed,
        FontWeight.w700,
      );
    }
    final angle = start + sweep * (value / max).clamp(0, 1);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final needle = Path()
      ..moveTo(-r * 0.17, -r * 0.024)
      ..lineTo(r * 0.75, -r * 0.007)
      ..lineTo(r * 0.75, r * 0.007)
      ..lineTo(-r * 0.17, r * 0.024)
      ..close();
    canvas.drawShadow(needle, Colors.black, 2, false);
    canvas.drawPath(needle, Paint()..color = needleRed);
    canvas.restore();
    canvas.drawCircle(c, r * 0.089, Paint()..color = const Color(0xff131716));
    canvas.drawCircle(
      c - Offset(r * 0.013, r * 0.018),
      r * 0.066,
      Paint()..color = const Color(0xff303330),
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color,
    FontWeight weight, {
    bool italic = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: weight,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      value != old.value || readout != old.readout || badge != old.badge;
}

class DualSpeedAccelGauge extends StatelessWidget {
  const DualSpeedAccelGauge({
    super.key,
    required this.speedMps,
    required this.accelMps2,
    required this.running,
    this.maxSpeedMph = 120.0,
    this.maxAccelMps2 = 5.0,
  });

  final double speedMps;
  final double accelMps2;
  final bool running;
  final double maxSpeedMph;
  final double maxAccelMps2;

  double get speedMph => speedMps * 2.23694;

  @override
  Widget build(BuildContext context) {
    final speed = speedMph.clamp(0.0, maxSpeedMph);
    final accel = accelMps2.clamp(-maxAccelMps2, maxAccelMps2);

    return Semantics(
      label: 'Speed: ${speed.round()} MPH, Acceleration: ${accel.toStringAsFixed(1)} m/s²',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: speed),
        duration: const Duration(milliseconds: 160),
        builder: (context, animatedSpeed, child) => TweenAnimationBuilder<double>(
          tween: Tween(end: accel),
          duration: const Duration(milliseconds: 160),
          builder: (context, animatedAccel, child) => CustomPaint(
            painter: _DualSpeedAccelGaugePainter(
              speedMph: animatedSpeed,
              accelMps2: animatedAccel,
              maxSpeedMph: maxSpeedMph,
              maxAccelMps2: maxAccelMps2,
              running: running,
            ),
          ),
        ),
      ),
    );
  }
}

class _DualSpeedAccelGaugePainter extends CustomPainter {
  _DualSpeedAccelGaugePainter({
    required this.speedMph,
    required this.accelMps2,
    required this.maxSpeedMph,
    required this.maxAccelMps2,
    required this.running,
  });

  final double speedMph;
  final double accelMps2;
  final double maxSpeedMph;
  final double maxAccelMps2;
  final bool running;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final bounds = Offset.zero & size;

    // Drop shadow
    canvas.drawCircle(
      c + Offset(0, r * 0.065),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    // Bezel outer metallic rim
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xff9e9b94),
            Color(0xff33332f),
            Color(0xff0a0a09),
            Color(0xff79766f),
          ],
        ).createShader(bounds),
    );

    // Bezel inner dark rings
    canvas.drawCircle(c, r * 0.965, Paint()..color = const Color(0xff141514));
    canvas.drawCircle(c, r * 0.906, Paint()..color = const Color(0xff5f605a));

    // Dial face (cream / ivory radial gradient)
    canvas.drawCircle(
      c,
      r * 0.892,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.25),
          colors: [Color(0xfff7f2e6), Color(0xffddd8cc), Color(0xffb4b0a6)],
          stops: [0, 0.8, 1],
        ).createShader(bounds),
    );

    // Center divider etched line
    final dividerPaint = Paint()
      ..color = const Color(0xff8a8579)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(c.dx - r * 0.65, c.dy),
      Offset(c.dx + r * 0.65, c.dy),
      dividerPaint,
    );

    // ==========================================
    // TOP SECTION: SPEED (0 to 120 MPH)
    // ==========================================
    _text(
      canvas,
      'SPEED',
      c - Offset(0, r * 0.62),
      r * 0.11,
      const Color(0xff242726),
      FontWeight.w700,
    );

    const speedStart = math.pi * 1.15;
    const speedSweep = math.pi * 0.70;
    final tickPaint = Paint()..strokeCap = StrokeCap.butt;
    const speedDivisions = 6; // 0, 20, 40, 60, 80, 100, 120
    for (int i = 0; i <= speedDivisions * 2; ++i) {
      final a = speedStart + speedSweep * i / (speedDivisions * 2);
      final major = i % 2 == 0;
      tickPaint
        ..color = const Color(0xff242726)
        ..strokeWidth = r * (major ? 0.016 : 0.008);
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (r * 0.84);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r * (major ? 0.74 : 0.79));
      canvas.drawLine(p1, p2, tickPaint);
      if (major) {
        final val = (maxSpeedMph * i / (speedDivisions * 2)).round();
        final textPos = c + Offset(math.cos(a), math.sin(a)) * (r * 0.64);
        _text(
          canvas,
          '$val',
          textPos,
          r * 0.11,
          const Color(0xff202322),
          FontWeight.w500,
        );
      }
    }

    // Speed digital display box
    final speedDisplay = Rect.fromCenter(
      center: c - Offset(0, r * 0.24),
      width: r * 0.70,
      height: r * 0.20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(speedDisplay, Radius.circular(r * 0.05)),
      Paint()..color = const Color(0xff202321),
    );
    _text(
      canvas,
      running ? '${speedMph.round()} MPH' : '0 MPH',
      speedDisplay.center,
      r * 0.125,
      const Color(0xffd9b989),
      FontWeight.w600,
    );

    // Speed needle (pointing into upper arc)
    final speedFrac = (speedMph / maxSpeedMph).clamp(0.0, 1.0);
    final speedAngle = speedStart + speedSweep * speedFrac;
    _drawNeedle(canvas, c, r * 0.76, speedAngle);

    // ==========================================
    // BOTTOM SECTION: ACCELERATION (-5 to +5 m/s²)
    // ==========================================
    _text(
      canvas,
      'ACCEL',
      c + Offset(0, r * 0.16),
      r * 0.10,
      const Color(0xff242726),
      FontWeight.w700,
    );

    const accelSweep = math.pi * 0.70;
    const accelCenter = math.pi * 0.5; // 90 deg (straight down)
    for (int i = -4; i <= 4; ++i) {
      final frac = i / 4.0; // -1.0 to +1.0
      final a = accelCenter - frac * (accelSweep / 2);
      final major = i % 2 == 0;
      tickPaint
        ..color = const Color(0xff242726)
        ..strokeWidth = r * (major ? 0.016 : 0.008);
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (r * 0.84);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r * (major ? 0.74 : 0.79));
      canvas.drawLine(p1, p2, tickPaint);
      if (major) {
        final val = (maxAccelMps2 * frac).abs().toStringAsFixed(frac == 0 ? 0 : 0);
        final labelStr = frac == 0 ? '0' : (frac > 0 ? '+$val' : '-$val');
        final textPos = c + Offset(math.cos(a), math.sin(a)) * (r * 0.64);
        _text(
          canvas,
          labelStr,
          textPos,
          r * 0.10,
          const Color(0xff202322),
          FontWeight.w500,
        );
      }
    }

    // Accel digital display box
    final accelDisplay = Rect.fromCenter(
      center: c + Offset(0, r * 0.44),
      width: r * 0.72,
      height: r * 0.20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(accelDisplay, Radius.circular(r * 0.05)),
      Paint()..color = const Color(0xff202321),
    );
    final accelPrefix = accelMps2 >= 0 ? '+' : '';
    final accelText = running
        ? '$accelPrefix${accelMps2.toStringAsFixed(1)} m/s²'
        : '0.0 m/s²';
    _text(
      canvas,
      accelText,
      accelDisplay.center,
      r * 0.115,
      const Color(0xffd9b989),
      FontWeight.w600,
    );

    // Accel needle (pointing into lower arc)
    final accelFrac = (accelMps2 / maxAccelMps2).clamp(-1.0, 1.0);
    final accelAngle = accelCenter - accelFrac * (accelSweep / 2);
    _drawNeedle(canvas, c, r * 0.76, accelAngle);

    // Center metallic cap overlapping both needles
    canvas.drawCircle(c, r * 0.09, Paint()..color = const Color(0xff131716));
    canvas.drawCircle(
      c - Offset(r * 0.012, r * 0.016),
      r * 0.065,
      Paint()..color = const Color(0xff303330),
    );
  }

  void _drawNeedle(Canvas canvas, Offset center, double length, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final needle = Path()
      ..moveTo(-length * 0.12, -length * 0.024)
      ..lineTo(length, -length * 0.007)
      ..lineTo(length, length * 0.007)
      ..lineTo(-length * 0.12, length * 0.024)
      ..close();
    canvas.drawShadow(needle, Colors.black, 2, false);
    canvas.drawPath(needle, Paint()..color = needleRed);
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color,
    FontWeight weight, {
    bool italic = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: weight,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_DualSpeedAccelGaugePainter old) =>
      speedMph != old.speedMph ||
      accelMps2 != old.accelMps2 ||
      running != old.running;
}

