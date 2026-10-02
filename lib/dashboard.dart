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
  });
  final double rpm, throttle, volume, maxRpm, boost, speedKmh;
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
              child: AnalogGauge(
                value: volume * 100,
                max: 100,
                divisions: 5,
                label: 'OUTPUT',
                unit: '%',
                readout: '${(volume * 100).round()}',
                auxiliary: true,
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
